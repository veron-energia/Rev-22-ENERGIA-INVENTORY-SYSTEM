-- 423_vouchers_services_prices_and_splits.sql
--
-- WHAT WAS WRONG (the audit of 8 Oct 2026, re-checked 9 Oct 2026:
-- THERAPY-14, THERAPY-18, THERAPY-13, THERAPY-17, STOCK-13)
--
--   Vouchers page (THERAPY-14). Delete wrote deleted_at straight into the
--   table, did not look at the answer, and did not say that customers still
--   held the voucher: on production the voucher deleted on 26 Sep 2026 still
--   has 13 units held by 10 customers. Nothing recorded who changed or deleted
--   a voucher; the vouchers table had no audit at all. "Use this price at
--   every store" also switched every store back on (set_voucher_price_all_
--   stores always sent available = true), so a store where the voucher was
--   switched off was switched on again by any edit (the page fix leaves the
--   box unticked when editing).
--
--   Therapy Services (THERAPY-18). Every save of a service wiped its notes:
--   the page sends no notes and upsert_therapy_service wrote
--   nullif(btrim(p_notes), '') over them (no service has notes on production
--   yet, 9 Oct 2026). The stores of a service were saved one store at a time,
--   so a failure part way left some stores saved and some not.
--
--   Split sales (THERAPY-13). create_split_credit_package_invoices and
--   create_split_premium_bundle_invoices took no request id. When the answer
--   to "Create invoices" was lost and staff pressed it again, a second group
--   of unpaid invoices was made for the same sale.
--
--   Holiday calendar (THERAPY-17). A region typed with spaces, or for "All
--   countries", was stored as typed; the calculation compares regions exactly,
--   so such a date silently applied to nobody.
--
--   Therapy store prices (STOCK-13). A therapy package's price at a store could
--   be saved below zero: set_unlimited_therapy_price had no check and the table
--   no constraint, unlike the voucher and promotion price tables. On
--   production 18 rows, none negative, none blank (9 Oct 2026).
--
-- THE RULES (the Owner asked on 9 Oct 2026 to finish the audit fixes
-- THERAPY-13, -14, -17, -18 and STOCK-13; the one price-history row (rule 1)
-- and the Singapore holiday country were answered on 9 Oct 2026)
--
--   1. Every change to a voucher, or to its price at a store, is in the audit
--      log: who, when, and the columns that changed, before and after. A
--      price change at a store leaves that one before-and-after row; the old
--      "voucher prices set" summary row is no longer written (the Owner, 9 Oct
--      2026). Audit rows already written are kept as they are.
--   2. Deleting a voucher marks it deleted and switches it off; it is never
--      removed, so past invoices and the vouchers customers hold still read
--      it. Owner and Manager only, as the page and the table rule have it.
--      When customers still hold it, a store still has it in stock, or a live
--      promotion, bundle or package offers it, the delete first says so and
--      waits for the caller to confirm. The reason given is kept.
--   3. "One price at every store" changes the price only; each store keeps
--      whether the voucher is on sale there (a store with no price yet gets
--      it on sale, as before).
--   4. Saving a therapy service keeps its notes unless notes are sent; an
--      empty text clears them.
--   5. A service's stores and prices are saved together: all of them or none.
--   6. A split sale sent again with the same request id gives back the sale
--      already made instead of making a second one. The same id for another
--      store, package or bundle, or for other customers, amounts or vouchers,
--      is refused: it is another sale, never answered as the first.
--   7. A holiday's region is trimmed; a blank region is none. A region needs a
--      country, and '*' (which stands for "the whole country") is not one.
--   8. A therapy package's price at a store is a number, 0 or more, or blank
--      (blank stops it being sold at that store). NaN is not a price.
--
-- WHAT THIS DOES
--
--   * trg_audit_voucher_change() (new; internal, the service role's alone,
--     339) and the triggers audit_voucher_change on vouchers and
--     audit_voucher_store_price_change on voucher_store_prices, after insert,
--     update or delete (rule 1). An update records only the columns that
--     changed and nothing at all when only updated_at or updated_by changed.
--     Actions: voucher_created, voucher_updated, voucher_deleted (deleted_at
--     set), voucher_restored (cleared), voucher_removed (the row deleted);
--     voucher_store_price_created, _updated, _removed, logged under the
--     voucher with the store. Module 'catalogue' and 'pricing'.
--   * set_voucher_prices(uuid,uuid,numeric,numeric,boolean) (patched; grants
--     kept): it no longer writes its own "voucher prices set" summary row, so
--     a price change has one history row, the trigger's before and after
--     (rule 1). A save that changes nothing leaves no row. The 33 summary
--     rows already on production (27 Jul to 23 Sep 2026) stay as they are.
--   * soft_delete_voucher(p_voucher_id, p_reason, p_confirmed) (new; signed-in
--     staff and the service role; first statement require_active_staff for
--     Owner and Manager): rule 2. Returns what depends on the voucher (the
--     customers holding it and how many units, the stock at each store, the
--     live promotions, premium bundles, credit packages and therapy packages
--     that offer it), and either needs_confirmation (nothing changed) or
--     deleted. A voucher already deleted is answered as deleted, so a retry is
--     safe. The audit row (by the trigger) carries the reason and the figures.
--   * set_voucher_price_all_stores(uuid,numeric,boolean) (replaced whole;
--     grants kept): a null p_available keeps each store's availability
--     (rule 3); true or false still sets it at every store, as before.
--   * upsert_therapy_service(...) (patched; grants kept): rule 4.
--   * set_therapy_service_stores(p_service_id, p_rows) (new; signed-in staff
--     and the service role; first statement require_active_staff for Owner,
--     Admin and Manager, as the page): rule 5. p_rows is a list of
--     {store_id, is_available, price_override}; a store that does not exist or
--     a negative price stops the whole save, naming the store. One audit row,
--     therapy_service_stores_saved. set_therapy_service_store (one store) is
--     kept as it is for the tests and scripts that call it.
--   * create_split_credit_package_invoices and
--     create_split_premium_bundle_invoices: a new last argument
--     p_request_id uuid DEFAULT NULL (rule 6). The old six-argument versions
--     are dropped in the same step (as 386 did), so the API has one function
--     of each name; the live page, which sends six arguments, reaches the new
--     one through the default and works as before. New first statement
--     require_store_access(p_store_id). With a request id: one call at a time
--     per id (an advisory lock), and a sale already made with it is returned
--     again with 'replayed': true and the same keys; an id used for another
--     store, package or bundle, or for other customers, amounts or vouchers
--     (compared with the allocations of the sale made), is refused. The
--     request id is stored on the split
--     group: credit_package_split_groups.request_id and
--     premium_bundle_split_groups.request_id (new, nullable) with a unique
--     index each (where not null). Everything else in both functions is
--     unchanged. Grants as before: signed-in logins and the service role.
--   * upsert_therapy_closure_date(...) (patched; grants kept): rule 7.
--   * set_unlimited_therapy_price(uuid,uuid,numeric,numeric,boolean) (patched;
--     grants kept): refuses a price below zero, and NaN (rule 8; NaN gets the
--     same "cannot be negative" message); set_therapy_price_all_stores reaches
--     it and so refuses one too.
--   * unlimited_therapy_store_prices: CHECK (selling_price IS NULL OR
--     (selling_price >= 0 AND selling_price <> 'NaN')), added NOT VALID and
--     then validated (0 rows break it on production: 18 rows, none negative,
--     none NaN, 9 Oct 2026).
--
-- NOT CHANGED
--
--   * Which vouchers can be given as rewards (THERAPY-7's server rule is
--     422's). The Vouchers page now shows and sets the existing
--     reward_eligible column for free-session (normal) vouchers, a column an
--     Owner or Manager could already write.
--   * set_therapy_price_all_stores and set_therapy_service_store. What
--     set_voucher_prices saves, and who may call it. The vouchers table
--     rules: an Owner or Manager may still write vouchers directly, and that
--     is now audited too.
--   * Existing audit rows: none is changed or removed.
--   * The 2027 Singapore holiday calendar. Marking it checked is a data change
--     the Owner approved (Q14, 9 Oct 2026); it is done by
--     scripts/therapy/repair/423-sg-2027-holidays-checked.sql after this, not
--     here. set_therapy_calendar_coverage, therapy_calendar_gaps and
--     therapy_apply_recalculation are unchanged; the page now asks before it
--     applies and takes a region.
--   * The holiday country of therapy periods. Setting Singapore on the
--     periods that have none (UTP-0000001 on 9 Oct 2026) is a data change the
--     Owner approved (9 Oct 2026); it is done by
--     scripts/therapy/repair/423-sg-holiday-country-on-periods.sql after
--     this, not here.
--   * The split functions' checks, money split, invoices, allocations and
--     answer. A call with no request id behaves exactly as before.
--   * No row of the app's tables is changed. Two columns, two indexes, one
--     constraint and two triggers are added.
--
-- SAFETY
--
--   Apart from the lock timeout this is one DO block, so it is atomic. Every
--   check is made and every new text built before anything is installed:
--     * each patched or replaced function is the production version read on
--       9 Oct 2026 (BEFORE), or already this migration's (AFTER), which is
--       left alone, so a re-run changes nothing;
--     * each new function is missing or already this version; for each split
--       function either the old six-argument version is there at BEFORE and
--       the new one is missing, or the old one is gone and the new one is at
--       AFTER;
--     * the functions relied on are the versions read on 9 Oct 2026; no other
--       function takes any of these names (the API picks an overload by
--       name);
--     * the columns used have the types read on 9 Oct 2026; the two audit
--       triggers are both missing or both exactly this migration's, no other
--       trigger on vouchers or voucher_store_prices writes the audit log, and
--       none is switched off (the voucher_discount_category trigger is not
--       read: 422 may change it, and the audit does not depend on it); the
--       new columns, indexes and constraint are missing or exactly this
--       migration's;
--     * every anchor occurs exactly once, and every text built has its AFTER
--       md5 before it is installed.
--   The patched texts are executed as CREATE OR REPLACE with the same
--   arguments and result types, which keeps owner and grants. The definitions
--   are read and compared with the search path set to public. Afterwards
--   every function has its AFTER md5 and the grants it had (the split
--   functions the grants the old ones had: signed-in logins and the service
--   role); the new client functions are signed-in logins' and the service
--   role's, never anon's or PUBLIC's; the trigger function is the service
--   role's alone; the triggers, columns, indexes and the validated constraint
--   are there. Then, switching role inside a block that is always undone,
--   with made-up rows (an Owner, a member of staff, two stores, vouchers, a
--   therapy service and package, a credit package and a bundle, and a
--   holiday country ZZ when there is none, all named 423 check): rules 1 to 8 are each tried once, a login with no profile
--   and the anon key are refused by the new functions, and nothing is
--   printed. No row remains. No invoice is made: the split replay is tried
--   with a group row made for the check.
--
-- BEFORE (production, 9 Oct 2026, after 413; md5 of pg_get_functiondef with
-- search_path public):
--   changed
--   set_voucher_price_all_stores(uuid,numeric,boolean)              28c6e12467f2518591c671ef4485738d
--   upsert_therapy_service(uuid,text,text,numeric,integer,text,integer,numeric,text,boolean,text)
--                                                                   c80468ba6c2ba803d9d267dff67e342e
--   upsert_therapy_closure_date(uuid,date,text,text,text,text,date,text,text,text)
--                                                                   3a67ddb2a98867336a2fddea06987239
--   set_unlimited_therapy_price(uuid,uuid,numeric,numeric,boolean)  f18a87d2c5d3b3d2043c7da123809dc4
--   set_voucher_prices(uuid,uuid,numeric,numeric,boolean)           ba35bf029c90181ea3a7538628af6077
--   create_split_credit_package_invoices(uuid,uuid,jsonb,uuid[],uuid,text)
--                                                                   6e3158086eb4fa718c88f2f4da039b69 (dropped)
--   create_split_premium_bundle_invoices(uuid,uuid,jsonb,uuid[],uuid,text)
--                                                                   b77a39b52089f314526ecaa666b28194 (dropped)
--   new: trg_audit_voucher_change(), soft_delete_voucher(uuid,text,boolean),
--   set_therapy_service_stores(uuid,jsonb),
--   create_split_credit_package_invoices(uuid,uuid,jsonb,uuid[],uuid,text,uuid),
--   create_split_premium_bundle_invoices(uuid,uuid,jsonb,uuid[],uuid,text,uuid) (missing)
--   relied on, not changed
--   require_active_staff(text[])                                    877b3aa74cea559881979bb161c450e2
--   require_store_access(uuid)                                      f9332fd2f0092337d64501d8a647c23f
--   current_user_role()                                             519b0a33a3548f970c5d585b6e76a389
--   is_owner_or_manager()                                           125dec10ce33b84ff5fb40a9bd455235
--   is_manager_or_above()                                           f12b9ed342070fa4defa30e4da2ba655
--   user_has_store_access(uuid)                                     8c82c6bcb64f496c5a05a2b8dafa95f8
--   set_therapy_price_all_stores(uuid,numeric,boolean)              658c8650af3d03f213df7255178b146e
--   set_therapy_service_store(uuid,uuid,boolean,numeric)            c4b9ee79b49a0fa905d07400c957814f
--   trg_voucher_discount_category()                                 61c13abb2993f552ef99d2b76c818705
--                                                     (read, not guarded: 422 may change it)
--   lock_invoice_date_history() (the trigger on audit_logs)         read, not guarded
--   public function fingerprint                                     675ac22c631079b58f06813d0d463fa3
--   Read again on production on 9 Oct 2026 after 414, 421 and 428 (public
--   function fingerprint 897ad364eff917861989315bb2fa0e43): every md5 above,
--   the columns, the triggers and the split functions' grants are unchanged,
--   the price table still has no check (18 rows, none negative or NaN), and
--   none of the new pieces is there. The fingerprint is not guarded: only
--   the md5s above and the schema checks below are. Read once more on
--   9 Oct 2026, when set_voucher_prices was added to the changed list
--   (fingerprint still 897ad364..., schema_migrations ending at 428): every
--   md5 above still matches, and no migration waiting in another worktree
--   (415-422, 424, 429, 431) names set_voucher_prices. Read again on
--   10 Oct 2026, after 415 was applied (schema_migrations ending at
--   20261010010418, fingerprint 566e76f702c89c9846968e6fdd89cc45): every md5
--   above, the columns, the triggers, the split functions' grants and the
--   price table (18 rows, none negative or NaN, no check) are unchanged, none
--   of the new pieces is there, and still no other migration waiting in a
--   worktree (416-418, 420, 422, 424, 429, 431) names set_voucher_prices.
-- AFTER (for later guards):
--   trg_audit_voucher_change()                                      59793e632d567d28a5917066a187411d
--   soft_delete_voucher(uuid,text,boolean)                          9507ace568f8b1b0a62e6c5b1500c780
--   set_therapy_service_stores(uuid,jsonb)                          1af40f0eb55c89dc3b18c5d2dc6d5c06
--   set_voucher_price_all_stores(uuid,numeric,boolean)              cdeb7d5ae3ee217130d75b6202decc1d
--   set_voucher_prices(uuid,uuid,numeric,numeric,boolean)           74818f40aed8eb3e92e9e5ec56cd97a1
--   upsert_therapy_service(...)                                     4d9f15d7519d3219a94f5664b525d466
--   upsert_therapy_closure_date(...)                                75904d1e4eb2006124da6fc415b813b4
--   set_unlimited_therapy_price(uuid,uuid,numeric,numeric,boolean)  7da0b210afa6951f8f8aa046976bf8a5
--   create_split_credit_package_invoices(uuid,uuid,jsonb,uuid[],uuid,text,uuid)
--                                                                   d9219dc95c3f5f598085161d31744d16
--   create_split_premium_bundle_invoices(uuid,uuid,jsonb,uuid[],uuid,text,uuid)
--                                                                   dfef28574f9c5b827d1093df1b5fc9b3
--   public function fingerprint, on production as of 10 Oct 2026 (after
--   414, 421, 428 and 415, 566e76f7...) if this is the next change
--                                                                   4e3399f965b2f28f40c3542a8b8c3f5a
--   (tested on a copy of production after 413 with 414, 421, 428 and 415
--   applied first, in that order; on that copy without 415 it is
--   c01690d2752450d122da082530a73341, and without any of them
--   a4e9f4c4e06a29b129e9c4fd02c7759e; other migrations of this round change
--   it too; the md5s above are the guard)
--
-- DEPLOY ORDER: this, then the front end (pushing to main deploys it). The
-- pages live now keep working against this: the split panels send six
-- arguments and reach the new functions through the default; the Vouchers
-- page's direct delete still works and is now audited; Therapy Services
-- sends no notes, which now keeps them; the store save loops
-- set_therapy_service_store as before. The new pages against a database
-- without this: the split panels' request id and the Vouchers page's Delete
-- and the services' store save would fail ("function not found"), so this
-- goes first. After this, with the Owner's approval, run the two data steps,
-- each as it is first (a dry run), then with c_apply set to true:
-- scripts/therapy/repair/423-sg-2027-holidays-checked.sql (Q14, 9 Oct 2026),
-- then scripts/therapy/repair/423-sg-holiday-country-on-periods.sql (Singapore
-- as the holiday country of the therapy periods that have none, 9 Oct 2026).
-- Neither needs the other or this migration; in this order the period it
-- lengthens is shown as checked straight away. Each data step opens with a
-- PREVIEW select that changes nothing. The steps report by notices, and the
-- MCP execute_sql tool does not show notices: there the dry run, the real
-- run and a second run all return []. So run the PREVIEW on its own first,
-- then the dry run and the real run, then the "To look afterwards" selects.
-- psql shows the notices.
-- B08's discount-voucher repair (STEP 2 of
-- scripts/therapy/repair-discount-vouchers-not-rewards.sql, which goes with
-- 422) is best run before this. Run after this, it leaves two history rows
-- per voucher: its own voucher_reward_switched_off and this trigger's
-- voucher_updated (reward_eligible true to false). Nothing is lost; its own
-- after-check counts only its own row.
-- The Vouchers page's "Discount vouchers are never rewards" and its Excel
-- "Can be a reward" column (No for every discount voucher) state 422's rule
-- (THERAPY-7), which this does not enforce: ship this front end only after
-- 422 is applied. 423 itself does not need 422.
--
-- Test: scripts/therapy/tests/vouchers-services-prices.sql (rules 1-5, 7, 8
-- and the grants) and scripts/therapy/tests/split-replay.sql (rule 6 with
-- real split invoices: a lost answer replayed, an id used for another sale,
-- a failed first try, no id, who may call), each applying this inside its own
-- rolled-back transaction; scripts/therapy/tests/split-replay-concurrency.mjs
-- (two presses at once, on a disposable copy with this applied);
-- scripts/permissions/tests/function-grants.sql and
-- scripts/permissions/tests/staff-only-functions.sql after it; the data steps:
-- scripts/therapy/tests/sg-2027-holidays-repair.sql and
-- scripts/therapy/tests/sg-holiday-country-repair.sql; the pages:
-- scripts/therapy/tests/vouchers-services-pages.test.mjs.

set lock_timeout = '5s';

do $mig$
declare
  -- ── New: the audit of a voucher and of its store prices ──────────────────
  c_audit_def constant text := $def$CREATE OR REPLACE FUNCTION public.trg_audit_voucher_change()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_row jsonb; v_prev jsonb; v_old jsonb; v_new jsonb; v_action text;
  v_record uuid; v_store uuid; v_module text; v_reason text; v_detail jsonb;
begin
  -- 423: every change to a voucher (vouchers) or to its price at a store
  -- (voucher_store_prices) goes in the audit log, whoever makes it: the
  -- Vouchers page, a server function or the SQL editor. An update records
  -- only the columns that changed, before and after, and nothing when only
  -- updated_at or updated_by changed. A price row is logged under its
  -- voucher, with the store, as set_voucher_prices logged it before 423; it
  -- is now the only row a price change leaves. The reason and
  -- the figures of a delete come from soft_delete_voucher, for its own update
  -- only.
  if tg_op = 'DELETE' then
    v_row := to_jsonb(old); v_old := v_row;
  elsif tg_op = 'INSERT' then
    v_row := to_jsonb(new); v_new := v_row;
  else
    v_row := to_jsonb(new); v_prev := to_jsonb(old);
    select coalesce(jsonb_object_agg(o.key, o.value), '{}'::jsonb) into v_old
      from jsonb_each(v_prev) o
     where o.key not in ('updated_at', 'updated_by') and o.value is distinct from v_row -> o.key;
    if v_old = '{}'::jsonb then
      return null;
    end if;
    select coalesce(jsonb_object_agg(n.key, n.value), '{}'::jsonb) into v_new
      from jsonb_each(v_row) n
     where v_old ? n.key;
  end if;

  if tg_table_name = 'vouchers' then
    v_record := (v_row ->> 'id')::uuid;
    v_module := 'catalogue';
    if tg_op = 'INSERT' then
      v_action := 'voucher_created';
    elsif tg_op = 'DELETE' then
      v_action := 'voucher_removed';
    elsif v_prev ->> 'deleted_at' is null and v_row ->> 'deleted_at' is not null then
      v_action := 'voucher_deleted';
      v_reason := nullif(current_setting('energia.voucher_change_reason', true), '');
      v_detail := nullif(current_setting('energia.voucher_change_detail', true), '')::jsonb;
      if v_detail is not null then
        v_new := v_new || jsonb_build_object('detail', v_detail);
      end if;
    elsif v_prev ->> 'deleted_at' is not null and v_row ->> 'deleted_at' is null then
      v_action := 'voucher_restored';
    else
      v_action := 'voucher_updated';
    end if;
  else
    v_record := (v_row ->> 'voucher_id')::uuid;
    v_store := (v_row ->> 'store_id')::uuid;
    v_module := 'pricing';
    v_action := case tg_op when 'INSERT' then 'voucher_store_price_created'
                           when 'DELETE' then 'voucher_store_price_removed'
                           else 'voucher_store_price_updated' end;
    if tg_op = 'UPDATE' then
      v_new := v_new || jsonb_build_object('store_id', v_store, 'price_row_id', v_row ->> 'id');
    end if;
  end if;

  insert into public.audit_logs
    (table_name, record_id, action, old_data, new_data, changed_by, actor_role, module, reason, store_id)
  values (tg_table_name, v_record, v_action, v_old, v_new,
          (select p.id from public.profiles p where p.id = auth.uid()),
          public.current_user_role()::text, v_module, v_reason, v_store);
  return null;
end
$function$
$def$;

  -- ── New: the Vouchers page's Delete ──────────────────────────────────────
  c_softdel_def constant text := $def$CREATE OR REPLACE FUNCTION public.soft_delete_voucher(p_voucher_id uuid, p_reason text DEFAULT NULL::text, p_confirmed boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v public.vouchers%rowtype; v_customers integer; v_units integer; v_stock jsonb;
  v_stock_total integer; v_used jsonb; v_used_total integer; v_detail jsonb;
begin
  -- 423: the Vouchers page's Delete (Owner and Manager, as the page and the
  -- table rule have it). A voucher is never removed: it is marked deleted and
  -- switched off, so past invoices and the vouchers customers hold still read
  -- it. First it says what still depends on it: the customers holding it
  -- (reward vouchers held) and how many, its stock at each store, and the
  -- live promotions, premium bundles, credit packages and therapy packages
  -- that offer it. When any of these is above zero nothing changes until the
  -- caller confirms (p_confirmed). A voucher already deleted is answered as
  -- deleted, so a retry is safe. The audit row (trg_audit_voucher_change)
  -- keeps the reason and these figures.
  perform public.require_active_staff(array['owner', 'manager']);
  select * into v from public.vouchers where id = p_voucher_id for update;
  if not found then
    raise exception 'That voucher no longer exists.'; end if;
  if v.deleted_at is not null then
    return jsonb_build_object('voucher_id', v.id, 'name', v.name, 'deleted', true,
                              'already_deleted', true, 'needs_confirmation', false);
  end if;

  select count(distinct r.customer_id)::integer, coalesce(sum(r.quantity), 0)::integer
    into v_customers, v_units
    from public.customer_reward_vouchers r
   where r.voucher_id = v.id and r.status = 'held';
  select coalesce(jsonb_agg(jsonb_build_object('store_id', s.store_id, 'store_name', st.name,
                                               'quantity', s.current_qty) order by st.name), '[]'::jsonb),
         coalesce(sum(s.current_qty), 0)::integer
    into v_stock, v_stock_total
    from public.voucher_store_stock s
    join public.stores st on st.id = s.store_id
   where s.voucher_id = v.id and s.current_qty > 0;
  v_used := jsonb_build_object(
    'promotions', (select count(*) from public.promotions p
                    where p.deleted_at is null and p.is_active
                      and (exists (select 1 from public.promotion_items i
                                    where i.promotion_id = p.id and i.voucher_id = v.id)
                           or exists (select 1 from public.promotion_choice_groups g
                                        join public.promotion_choice_options o on o.group_id = g.id
                                       where g.promotion_id = p.id and o.voucher_id = v.id))),
    'premium_bundles', (select count(*) from public.premium_bundles b
                         where b.deleted_at is null and b.is_active
                           and exists (select 1 from public.premium_bundle_vouchers x
                                        where x.bundle_id = b.id and x.voucher_id = v.id)),
    'credit_packages', (select count(*) from public.credit_packages c
                         where c.deleted_at is null and c.is_active
                           and exists (select 1 from public.credit_package_vouchers x
                                        where x.package_id = c.id and x.voucher_id = v.id)),
    'therapy_packages', (select count(*) from public.unlimited_therapy_packages t
                          where t.deleted_at is null and t.is_active
                            and (t.voucher_id = v.id
                                 or exists (select 1 from public.therapy_package_vouchers x
                                             where x.package_id = t.id and x.voucher_id = v.id))));
  select coalesce(sum(e.value::integer), 0)::integer into v_used_total from jsonb_each_text(v_used) e;
  v_detail := jsonb_build_object('holders_customers', v_customers, 'holders_units', v_units,
                                 'store_stock', v_stock, 'store_stock_total', v_stock_total,
                                 'used_in', v_used, 'used_in_total', v_used_total);

  if not coalesce(p_confirmed, false) and (v_units > 0 or v_stock_total > 0 or v_used_total > 0) then
    return jsonb_build_object('voucher_id', v.id, 'name', v.name, 'deleted', false,
                              'needs_confirmation', true) || v_detail;
  end if;

  perform set_config('energia.voucher_change_reason', coalesce(btrim(p_reason), ''), true);
  perform set_config('energia.voucher_change_detail', v_detail::text, true);
  update public.vouchers set deleted_at = now(), is_active = false where id = v.id;
  perform set_config('energia.voucher_change_reason', '', true);
  perform set_config('energia.voucher_change_detail', '', true);
  return jsonb_build_object('voucher_id', v.id, 'name', v.name, 'deleted', true,
                            'needs_confirmation', false) || v_detail;
end
$function$
$def$;

  -- ── New: a service's stores and prices, saved together ───────────────────
  c_stores_def constant text := $def$CREATE OR REPLACE FUNCTION public.set_therapy_service_stores(p_service_id uuid, p_rows jsonb)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r jsonb; v_store uuid; v_name text; v_price numeric; v_n integer := 0;
begin
  -- 423: the Therapy Services page's "stores and prices" window, saved in one
  -- go: every row or none. A row is {store_id, is_available, price_override};
  -- a blank price charges the standard price. A store that no longer exists,
  -- or a price below zero, stops the whole save and names the store. Owner,
  -- Admin and Manager, as the page (set_therapy_service_store, for one store,
  -- is unchanged).
  perform public.require_active_staff(array['owner', 'admin', 'manager']);
  perform 1 from public.therapy_services s where s.id = p_service_id and s.deleted_at is null for update;
  if not found then
    raise exception 'That service no longer exists'; end if;
  if p_rows is null or jsonb_typeof(p_rows) <> 'array' then
    raise exception 'Send the stores as a list'; end if;
  for r in select * from jsonb_array_elements(p_rows) loop
    v_store := nullif(r ->> 'store_id', '')::uuid;
    select st.name into v_name from public.stores st where st.id = v_store;
    if v_store is null or v_name is null then
      raise exception 'A store in this list no longer exists. Close the window and open it again.'; end if;
    v_price := nullif(r ->> 'price_override', '')::numeric;
    if v_price is not null and not (v_price >= 0 and v_price <> 'NaN'::numeric) then
      raise exception 'The price at % cannot be negative. Leave it empty to charge the standard price.', v_name; end if;
    insert into public.therapy_service_stores (service_id, store_id, is_available, price_override)
    values (p_service_id, v_store, coalesce((r ->> 'is_available')::boolean, false), v_price)
    on conflict (service_id, store_id) do update
      set is_available = excluded.is_available, price_override = excluded.price_override,
          updated_at = now();
    v_n := v_n + 1;
  end loop;
  insert into public.audit_logs (table_name, record_id, action, new_data, changed_by, actor_role, module)
  values ('therapy_services', p_service_id, 'therapy_service_stores_saved', jsonb_build_object('stores', p_rows),
          (select p.id from public.profiles p where p.id = auth.uid()),
          public.current_user_role()::text, 'therapy');
  return v_n;
end
$function$
$def$;

  -- ── Replaced whole: one voucher price at every store ─────────────────────
  c_vpall_def constant text := $def$CREATE OR REPLACE FUNCTION public.set_voucher_price_all_stores(p_voucher_id uuid, p_price numeric, p_available boolean DEFAULT true)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_s record; v_n integer := 0;
begin
  if not public.is_owner_or_manager() then
    raise exception 'Only an Owner or Manager can edit voucher prices'; end if;
  -- 423: a null p_available keeps whether the voucher is on sale at each
  -- store (a store with no price yet: on sale), so one price for every store
  -- no longer switches a store back on. true or false still sets it
  -- everywhere, as before.
  for v_s in
    select s.id, coalesce(vp.available_at_store, true) as available
      from public.stores s
      left join public.voucher_store_prices vp
        on vp.voucher_id = p_voucher_id and vp.store_id = s.id and vp.deleted_at is null
     where s.deleted_at is null and coalesce(s.is_active, true)
  loop
    perform public.set_voucher_prices(p_voucher_id, v_s.id, p_price, p_price, coalesce(p_available, v_s.available));
    v_n := v_n + 1;
  end loop;
  return v_n;
end $function$
$def$;

  -- ── Anchors ───────────────────────────────────────────────────────────────
  -- set_voucher_prices: no summary row; the trigger's before and after is the
  -- one row a price change leaves (the Owner, 9 Oct 2026).
  c_vp_a constant text := $q$  perform public.write_audit_ex('voucher_store_prices', p_voucher_id, 'voucher_prices_set',
    null, jsonb_build_object('store', p_store_id, 'price', v_price), 'pricing', null, p_store_id);
$q$;
  c_vp_r constant text := $q$  -- 423: no "voucher prices set" summary row any more. The audit trigger on
  -- voucher_store_prices logs the row's before and after, and that is the one
  -- history row of a price change (the Owner, 9 Oct 2026).
$q$;

  -- upsert_therapy_service: notes kept when none are sent.
  c_svc_a constant text := $q$           is_active = coalesce(p_is_active, false), notes = nullif(btrim(p_notes), ''),
$q$;
  c_svc_r constant text := $q$           is_active = coalesce(p_is_active, false),
           -- 423: the notes are kept when none are sent (null); an empty text clears them.
           notes = case when p_notes is null then notes else nullif(btrim(p_notes), '') end,
$q$;

  -- upsert_therapy_closure_date: the region trimmed, and only with a country.
  c_cl_decl_a constant text := $q$declare v_id uuid;
$q$;
  c_cl_decl_r constant text := $q$declare v_id uuid;
  v_region text := nullif(btrim(p_region), '');  -- 423: trimmed; blank is none
$q$;
  c_cl_check_a constant text := $q$  if coalesce(nullif(btrim(p_name), ''), '') = '' then raise exception 'A name is required'; end if;
$q$;
  c_cl_check_r constant text := $q$  if coalesce(nullif(btrim(p_name), ''), '') = '' then raise exception 'A name is required'; end if;
  -- 423: holidays are matched to a customer's region exactly, so a region
  -- belongs to a country (a date for all countries has none), and '*', which
  -- stands for the whole country, is not a region.
  if v_region is not null and p_country is null then
    raise exception 'Choose the country this region belongs to, or leave the region blank'; end if;
  if v_region = '*' then
    raise exception 'Leave the region blank for the whole country'; end if;
$q$;
  c_cl_ins_a constant text := $q$    values (p_date, p_kind, btrim(p_name), p_country, p_region, p_observed_for,
$q$;
  c_cl_ins_r constant text := $q$    values (p_date, p_kind, btrim(p_name), p_country, v_region, p_observed_for,
$q$;
  c_cl_upd_a constant text := $q$           region = p_region, observed_for = p_observed_for, source = p_source,
$q$;
  c_cl_upd_r constant text := $q$           region = v_region, observed_for = p_observed_for, source = p_source,
$q$;

  -- set_unlimited_therapy_price: never below zero.
  c_ut_a constant text := $q$  if not public.is_owner_or_manager() then raise exception 'Only an Owner or Manager can set therapy prices'; end if;
$q$;
  c_ut_r constant text := $q$  if not public.is_owner_or_manager() then raise exception 'Only an Owner or Manager can set therapy prices'; end if;
  -- 423: 0 or more, or blank (blank stops it being sold at this store).
  if v_price is not null and not (v_price >= 0 and v_price <> 'NaN'::numeric) then
    raise exception 'Price cannot be negative. Enter 0 or more, or leave it blank to stop selling it at this store.'; end if;
$q$;

  -- create_split_credit_package_invoices: a request id, replayed.
  c_cp_head_a constant text := $q$p_notes text DEFAULT NULL::text)
 RETURNS jsonb
$q$;
  c_cp_head_r constant text := $q$p_notes text DEFAULT NULL::text, p_request_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
$q$;
  c_cp_begin_a constant text := $q$  v_invoices jsonb := '[]'::jsonb;
begin
  -- ---- store access ----
  if not public.user_has_store_access(p_store_id) then
    raise exception 'You do not have access to this store'; end if;
$q$;
  c_cp_begin_r constant text := $q$  v_invoices jsonb := '[]'::jsonb;
  v_prior public.credit_package_split_groups%rowtype;  -- 423
begin
  perform public.require_store_access(p_store_id);  -- 423: active staff of this store
  -- ---- store access ----
  if not public.user_has_store_access(p_store_id) then
    raise exception 'You do not have access to this store'; end if;

  -- 423: a request id makes a retry safe. The panel makes one when it opens
  -- and sends it with every try. When a sale was already made with it (its
  -- answer was lost, say), that sale is returned again and nothing new is
  -- made. One call at a time per id.
  if p_request_id is not null then
    perform pg_advisory_xact_lock(hashtextextended('create_split_credit_package_invoices:' || p_request_id::text, 0));
    select * into v_prior from public.credit_package_split_groups g where g.request_id = p_request_id;
    if found then
      if v_prior.store_id <> p_store_id or v_prior.credit_package_id <> p_credit_package_id then
        raise exception 'This request was already used for another sale. Close the split and start again.'; end if;
      -- The same customers paying the same amounts, with the same reward
      -- vouchers, or it is another sale: refused, never answered as this one.
      if (select coalesce(array_agg(s.k order by s.k), '{}')
            from (select a.customer_id::text || '|' || round(a.payment_amount, 2)::text
                         || '|' || coalesce(a.reward_voucher_qty, 0)::text as k
                    from public.credit_package_split_allocations a
                   where a.split_group_id = v_prior.id) s)
         is distinct from
         (select coalesce(array_agg(s.k order by s.k), '{}')
            from (select (x ->> 'customer_id')::uuid::text || '|' || round((x ->> 'payment_amount')::numeric, 2)::text
                         || '|' || coalesce((x ->> 'reward_voucher_qty')::integer, 0)::text as k
                    from jsonb_array_elements(case when jsonb_typeof(p_allocations) = 'array'
                                                   then p_allocations else '[]'::jsonb end) x) s) then
        raise exception 'This request was already used for another sale. Close the split and start again.'; end if;
      return jsonb_build_object(
        'split_group_id', v_prior.id, 'package_name', v_prior.package_name_snapshot,
        'package_price', v_prior.package_price_snapshot,
        'paid_credit_total', v_prior.paid_credit_total_snapshot,
        'bonus_credit_total', v_prior.bonus_credit_total_snapshot,
        'reward_voucher_total', v_prior.reward_voucher_total_snapshot,
        'invoices', coalesce((
          select jsonb_agg(jsonb_build_object(
                   'invoice_id', a.invoice_id, 'invoice_no', i.invoice_no, 'customer_id', a.customer_id,
                   'payment_amount', a.payment_amount, 'paid_credit', a.paid_credit_amount,
                   'bonus_credit', a.bonus_credit_amount, 'reward_vouchers', a.reward_voucher_qty)
                   order by i.invoice_no, a.id)
            from public.credit_package_split_allocations a
            left join public.invoices i on i.id = a.invoice_id
           where a.split_group_id = v_prior.id), '[]'::jsonb),
        'replayed', true);
    end if;
  end if;
$q$;
  c_cp_ins_a constant text := $q$    customer_count, created_by)
  values (p_store_id, pk.id, pk.name, pk.customer_price,
    pk.paid_credit_amount, v_bonus_total, v_reward_total, v_n, auth.uid())
$q$;
  c_cp_ins_r constant text := $q$    customer_count, created_by, request_id)
  values (p_store_id, pk.id, pk.name, pk.customer_price,
    pk.paid_credit_amount, v_bonus_total, v_reward_total, v_n, auth.uid(), p_request_id)
$q$;

  -- create_split_premium_bundle_invoices: a request id, replayed.
  c_pb_begin_a constant text := $q$  v_invoices jsonb := '[]'::jsonb;
begin
  if not public.user_has_store_access(p_store_id) then
    raise exception 'You do not have access to this store'; end if;
$q$;
  c_pb_begin_r constant text := $q$  v_invoices jsonb := '[]'::jsonb;
  v_prior public.premium_bundle_split_groups%rowtype;  -- 423
begin
  perform public.require_store_access(p_store_id);  -- 423: active staff of this store
  if not public.user_has_store_access(p_store_id) then
    raise exception 'You do not have access to this store'; end if;

  -- 423: a request id makes a retry safe. The panel makes one when it opens
  -- and sends it with every try. When a sale was already made with it (its
  -- answer was lost, say), that sale is returned again and nothing new is
  -- made. One call at a time per id.
  if p_request_id is not null then
    perform pg_advisory_xact_lock(hashtextextended('create_split_premium_bundle_invoices:' || p_request_id::text, 0));
    select * into v_prior from public.premium_bundle_split_groups g where g.request_id = p_request_id;
    if found then
      if v_prior.store_id <> p_store_id or v_prior.premium_bundle_id <> p_premium_bundle_id then
        raise exception 'This request was already used for another sale. Close the split and start again.'; end if;
      -- The same customers paying the same amounts, with the same number of
      -- free vouchers each, or it is another sale: refused, never answered as
      -- this one.
      if (select coalesce(array_agg(s.k order by s.k), '{}')
            from (select a.customer_id::text || '|' || round(a.payment_amount, 2)::text
                         || '|' || coalesce(a.voucher_qty, 0)::text as k
                    from public.premium_bundle_split_allocations a
                   where a.split_group_id = v_prior.id) s)
         is distinct from
         (select coalesce(array_agg(s.k order by s.k), '{}')
            from (select (x ->> 'customer_id')::uuid::text || '|' || round((x ->> 'payment_amount')::numeric, 2)::text
                         || '|' || (select coalesce(sum(coalesce((q ->> 'quantity')::integer, 0)), 0)
                                      from jsonb_array_elements(case when jsonb_typeof(x -> 'voucher_selection') = 'array'
                                                                     then x -> 'voucher_selection' else '[]'::jsonb end) q)::text as k
                    from jsonb_array_elements(case when jsonb_typeof(p_allocations) = 'array'
                                                   then p_allocations else '[]'::jsonb end) x) s) then
        raise exception 'This request was already used for another sale. Close the split and start again.'; end if;
      return jsonb_build_object(
        'split_group_id', v_prior.id, 'bundle_name', v_prior.bundle_name_snapshot,
        'bundle_price', v_prior.payment_snapshot,
        'paid_credit_total', v_prior.paid_credit_total_snapshot,
        'bonus_credit_total', v_prior.bonus_credit_total_snapshot,
        'reward_voucher_total', v_prior.free_voucher_total_snapshot,
        'invoices', coalesce((
          select jsonb_agg(jsonb_build_object(
                   'invoice_id', a.invoice_id, 'invoice_no', i.invoice_no, 'customer_id', a.customer_id,
                   'payment_amount', a.payment_amount, 'paid_credit', a.paid_credit_amount,
                   'bonus_credit', a.bonus_credit_amount, 'reward_vouchers', a.voucher_qty)
                   order by i.invoice_no, a.id)
            from public.premium_bundle_split_allocations a
            left join public.invoices i on i.id = a.invoice_id
           where a.split_group_id = v_prior.id), '[]'::jsonb),
        'replayed', true);
    end if;
  end if;
$q$;
  c_pb_ins_a constant text := $q$    customer_count, created_by)
  values (p_store_id, b.id, b.name, b.customer_payment_amount,
    b.paid_credit_amount, b.bonus_credit_amount, coalesce(b.free_voucher_qty,0), v_n, auth.uid())
$q$;
  c_pb_ins_r constant text := $q$    customer_count, created_by, request_id)
  values (p_store_id, b.id, b.name, b.customer_payment_amount,
    b.paid_credit_amount, b.bonus_credit_amount, coalesce(b.free_voucher_qty,0), v_n, auth.uid(), p_request_id)
$q$;

  -- ── md5s ─────────────────────────────────────────────────────────────────
  c_audit_after   constant text := '59793e632d567d28a5917066a187411d';
  c_softdel_after constant text := '9507ace568f8b1b0a62e6c5b1500c780';
  c_stores_after  constant text := '1af40f0eb55c89dc3b18c5d2dc6d5c06';
  c_vpall_after   constant text := 'cdeb7d5ae3ee217130d75b6202decc1d';
  c_vp_after      constant text := '74818f40aed8eb3e92e9e5ec56cd97a1';
  c_svc_after     constant text := '4d9f15d7519d3219a94f5664b525d466';
  c_cl_after      constant text := '75904d1e4eb2006124da6fc415b813b4';
  c_ut_after      constant text := '7da0b210afa6951f8f8aa046976bf8a5';
  c_cp_after      constant text := 'd9219dc95c3f5f598085161d31744d16';
  c_pb_after      constant text := 'dfef28574f9c5b827d1093df1b5fc9b3';
  c_cp_old constant text := 'create_split_credit_package_invoices(uuid,uuid,jsonb,uuid[],uuid,text)';
  c_pb_old constant text := 'create_split_premium_bundle_invoices(uuid,uuid,jsonb,uuid[],uuid,text)';
  c_cp_new constant text := 'create_split_credit_package_invoices(uuid,uuid,jsonb,uuid[],uuid,text,uuid)';
  c_pb_new constant text := 'create_split_premium_bundle_invoices(uuid,uuid,jsonb,uuid[],uuid,text,uuid)';
  c_cp_old_md5 constant text := '6e3158086eb4fa718c88f2f4da039b69';
  c_pb_old_md5 constant text := 'b77a39b52089f314526ecaa666b28194';

  -- The triggers and the schema pieces this adds, as pg_get_*def prints them.
  c_trg_v constant text := 'CREATE TRIGGER audit_voucher_change AFTER INSERT OR DELETE OR UPDATE ON public.vouchers FOR EACH ROW EXECUTE FUNCTION trg_audit_voucher_change()';
  c_trg_vp constant text := 'CREATE TRIGGER audit_voucher_store_price_change AFTER INSERT OR DELETE OR UPDATE ON public.voucher_store_prices FOR EACH ROW EXECUTE FUNCTION trg_audit_voucher_change()';
  c_ix_cp constant text := 'CREATE UNIQUE INDEX credit_package_split_groups_request_id_key ON public.credit_package_split_groups USING btree (request_id) WHERE (request_id IS NOT NULL)';
  c_ix_pb constant text := 'CREATE UNIQUE INDEX premium_bundle_split_groups_request_id_key ON public.premium_bundle_split_groups USING btree (request_id) WHERE (request_id IS NOT NULL)';
  c_chk_name constant text := 'unlimited_therapy_store_prices_selling_price_check';
  c_chk_def constant text := 'CHECK (((selling_price IS NULL) OR ((selling_price >= (0)::numeric) AND (selling_price <> ''NaN''::numeric))))';
  -- The columns these use, as read on 9 Oct 2026 (name type, by name). Other
  -- columns may come and go: the audit copies whole rows.
  c_cols_v constant text := 'code text|deleted_at timestamp with time zone|id uuid|is_active boolean|name text|selling_price numeric(12,2)|voucher_kind voucher_kind';
  c_cols_vp constant text := 'available_at_store boolean|deleted_at timestamp with time zone|id uuid|selling_price numeric(12,2)|store_id uuid|updated_at timestamp with time zone|updated_by uuid|voucher_id uuid';
  c_cols_audit constant text := 'action text|actor_role text|changed_by uuid|module text|new_data jsonb|old_data jsonb|reason text|record_id uuid|store_id uuid|table_name text';

  v_path text := current_setting('search_path');
  v_claims text := current_setting('request.jwt.claims', true);
  r record; d text; v text; n int; k int; i int; v_bad text;
  v_fns text[] := '{}'; v_defs text[] := '{}'; v_acl text[];
  v_cp_mode text; v_pb_mode text; v_trg_v_new boolean; v_trg_vp_new boolean; v_chk_new boolean;
  v_owner uuid; v_staff uuid; v_store uuid; v_store2 uuid; v_v1 uuid; v_v2 uuid; v_svc uuid; v_pkg uuid;
  v_cpk uuid; v_cpk2 uuid; v_pbk uuid; v_pbk2 uuid; v_grp uuid; v_req uuid; v_res jsonb; v_cl uuid;
begin
  -- The definitions are read and compared with public alone on the search
  -- path, as they were read on 9 Oct 2026.
  perform set_config('search_path', 'public', true);

  -- ── Guards, anchors and new texts: nothing is installed unless all pass ────
  -- New whole functions: missing, or already this version.
  for r in select * from (values
    ('trg_audit_voucher_change()', c_audit_after, c_audit_def),
    ('soft_delete_voucher(uuid,text,boolean)', c_softdel_after, c_softdel_def),
    ('set_therapy_service_stores(uuid,jsonb)', c_stores_after, c_stores_def)) x(fn, after_md5, def)
  loop
    if md5(r.def) <> r.after_md5 then
      v_bad := concat_ws('; ', v_bad, r.fn || ' built ' || md5(r.def)); end if;
    if to_regprocedure('public.' || r.fn) is null then
      v_fns := v_fns || r.fn; v_defs := v_defs || r.def;
    elsif md5(pg_get_functiondef(to_regprocedure('public.' || r.fn))) <> r.after_md5 then
      raise exception '423: public.% already exists with another text (md5 %). Re-read it and re-test before applying.',
        r.fn, md5(pg_get_functiondef(to_regprocedure('public.' || r.fn)));
    end if;
  end loop;

  -- Patched or replaced: BEFORE (to change) or AFTER (left alone).
  for r in select * from (values
    ('set_voucher_price_all_stores(uuid,numeric,boolean)', '28c6e12467f2518591c671ef4485738d', c_vpall_after,
     c_vpall_def, null::text[]),
    ('set_voucher_prices(uuid,uuid,numeric,numeric,boolean)', 'ba35bf029c90181ea3a7538628af6077', c_vp_after,
     null::text, array[[c_vp_a, c_vp_r]]),
    ('upsert_therapy_service(uuid,text,text,numeric,integer,text,integer,numeric,text,boolean,text)',
     'c80468ba6c2ba803d9d267dff67e342e', c_svc_after, null::text, array[[c_svc_a, c_svc_r]]),
    ('upsert_therapy_closure_date(uuid,date,text,text,text,text,date,text,text,text)',
     '3a67ddb2a98867336a2fddea06987239', c_cl_after, null::text,
     array[[c_cl_decl_a, c_cl_decl_r], [c_cl_check_a, c_cl_check_r], [c_cl_ins_a, c_cl_ins_r], [c_cl_upd_a, c_cl_upd_r]]),
    ('set_unlimited_therapy_price(uuid,uuid,numeric,numeric,boolean)', 'f18a87d2c5d3b3d2043c7da123809dc4', c_ut_after,
     null::text, array[[c_ut_a, c_ut_r]])
  ) x(fn, before_md5, after_md5, whole, edits)
  loop
    if to_regprocedure('public.' || r.fn) is null then
      raise exception '423: public.% is missing', r.fn; end if;
    d := pg_get_functiondef(to_regprocedure('public.' || r.fn));
    v := md5(d);
    if v = r.after_md5 then
      raise notice '423: public.% is already this version; left alone', r.fn;
      continue;
    elsif v <> r.before_md5 then
      raise exception '423: public.% is not the version this was tested against (md5 %). Re-read it from production and re-test before applying.', r.fn, v;
    end if;
    if r.edits is null then
      d := r.whole;
    else
      for k in 1 .. array_length(r.edits, 1) loop
        n := (length(d) - length(replace(d, r.edits[k][1], ''))) / length(r.edits[k][1]);
        if n <> 1 then
          raise exception '423: anchor % of public.% was found % times, not once', k, r.fn, n; end if;
        d := replace(d, r.edits[k][1], r.edits[k][2]);
      end loop;
    end if;
    if md5(d) <> r.after_md5 then
      v_bad := concat_ws('; ', v_bad, r.fn || ' built ' || md5(d)); end if;
    v_fns := v_fns || r.fn; v_defs := v_defs || d;
  end loop;

  -- The split functions: the old six-argument version at BEFORE and no new
  -- one (build the new one from it), or no old one and the new one at AFTER.
  for r in select * from (values
    ('cp', c_cp_old, c_cp_new, c_cp_old_md5, c_cp_after, array[[c_cp_head_a, c_cp_head_r], [c_cp_begin_a, c_cp_begin_r], [c_cp_ins_a, c_cp_ins_r]]),
    ('pb', c_pb_old, c_pb_new, c_pb_old_md5, c_pb_after, array[[c_cp_head_a, c_cp_head_r], [c_pb_begin_a, c_pb_begin_r], [c_pb_ins_a, c_pb_ins_r]])
  ) x(tag, old_sig, new_sig, old_md5, after_md5, edits)
  loop
    if to_regprocedure('public.' || r.old_sig) is null and to_regprocedure('public.' || r.new_sig) is not null
       and md5(pg_get_functiondef(to_regprocedure('public.' || r.new_sig))) = r.after_md5 then
      raise notice '423: public.% is already this version; left alone', r.new_sig;
      if r.tag = 'cp' then v_cp_mode := 'done'; else v_pb_mode := 'done'; end if;
      continue;
    end if;
    if to_regprocedure('public.' || r.new_sig) is not null then
      raise exception '423: public.% exists with another text, or beside the old version. Re-read and re-test.', r.new_sig; end if;
    if to_regprocedure('public.' || r.old_sig) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || r.old_sig))) <> r.old_md5 then
      raise exception '423: public.% is missing or not the version this was tested against. Re-read it from production and re-test before applying.', r.old_sig; end if;
    d := pg_get_functiondef(to_regprocedure('public.' || r.old_sig));
    for k in 1 .. array_length(r.edits, 1) loop
      n := (length(d) - length(replace(d, r.edits[k][1], ''))) / length(r.edits[k][1]);
      if n <> 1 then
        raise exception '423: anchor % of public.% was found % times, not once', k, r.old_sig, n; end if;
      d := replace(d, r.edits[k][1], r.edits[k][2]);
    end loop;
    if md5(d) <> r.after_md5 then
      v_bad := concat_ws('; ', v_bad, r.new_sig || ' built ' || md5(d)); end if;
    if r.tag = 'cp' then v_cp_mode := 'build'; else v_pb_mode := 'build'; end if;
    v_fns := v_fns || r.new_sig; v_defs := v_defs || d;
  end loop;

  if v_bad is not null then
    raise exception '423: a text built is not the tested one: %', v_bad; end if;

  -- Relied on, not changed: the versions read on 9 Oct 2026.
  for r in select * from (values
    ('require_active_staff(text[])', '877b3aa74cea559881979bb161c450e2'),
    ('require_store_access(uuid)', 'f9332fd2f0092337d64501d8a647c23f'),
    ('current_user_role()', '519b0a33a3548f970c5d585b6e76a389'),
    ('is_owner_or_manager()', '125dec10ce33b84ff5fb40a9bd455235'),
    ('is_manager_or_above()', 'f12b9ed342070fa4defa30e4da2ba655'),
    ('user_has_store_access(uuid)', '8c82c6bcb64f496c5a05a2b8dafa95f8'),
    ('set_therapy_price_all_stores(uuid,numeric,boolean)', '658c8650af3d03f213df7255178b146e'),
    ('set_therapy_service_store(uuid,uuid,boolean,numeric)', 'c4b9ee79b49a0fa905d07400c957814f')) x(fn, md5)
  loop
    if to_regprocedure('public.' || r.fn) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || r.fn))) <> r.md5 then
      raise exception '423: public.% is missing or not the version read on 9 Oct 2026. Re-read it from production and re-test before applying.', r.fn; end if;
  end loop;

  -- No other function takes these names (the API picks an overload by name).
  select string_agg(p.oid::regprocedure::text, ', ') into v_bad from pg_proc p
   where p.pronamespace = 'public'::regnamespace
     and p.proname in ('trg_audit_voucher_change', 'soft_delete_voucher', 'set_therapy_service_stores',
                       'set_voucher_price_all_stores', 'set_voucher_prices', 'upsert_therapy_service',
                       'upsert_therapy_closure_date', 'set_unlimited_therapy_price',
                       'create_split_credit_package_invoices', 'create_split_premium_bundle_invoices')
     and p.oid::regprocedure::text not in (
       'trg_audit_voucher_change()', 'soft_delete_voucher(uuid,text,boolean)', 'set_therapy_service_stores(uuid,jsonb)',
       'set_voucher_price_all_stores(uuid,numeric,boolean)', 'set_voucher_prices(uuid,uuid,numeric,numeric,boolean)',
       'upsert_therapy_service(uuid,text,text,numeric,integer,text,integer,numeric,text,boolean,text)',
       'upsert_therapy_closure_date(uuid,date,text,text,text,text,date,text,text,text)',
       'set_unlimited_therapy_price(uuid,uuid,numeric,numeric,boolean)', c_cp_old, c_pb_old, c_cp_new, c_pb_new);
  if v_bad is not null then
    raise exception '423: another function takes one of these names: %', v_bad; end if;

  -- The columns used, as read on 9 Oct 2026.
  for r in select * from (values
    ('public.vouchers', c_cols_v), ('public.voucher_store_prices', c_cols_vp), ('public.audit_logs', c_cols_audit)) x(tbl, cols)
  loop
    select string_agg(a.attname || ' ' || format_type(a.atttypid, a.atttypmod), '|' order by a.attname) into v
      from pg_attribute a
     where a.attrelid = r.tbl::regclass and a.attnum > 0 and not a.attisdropped
       and a.attname in (select split_part(c, ' ', 1) from unnest(string_to_array(r.cols, '|')) c);
    if v is distinct from r.cols then
      raise exception '423: % is not shaped as read on 9 Oct 2026 (%)', r.tbl, v; end if;
  end loop;
  -- The audit triggers: both missing or both exactly this migration's, with
  -- their function. No other trigger on the two tables writes the audit log
  -- (a change would be logged twice), and none is switched off.
  select pg_get_triggerdef(t.oid) into v from pg_trigger t
   where t.tgrelid = 'public.vouchers'::regclass and t.tgname = 'audit_voucher_change' and not t.tgisinternal;
  if v is not null and v <> c_trg_v then
    raise exception '423: public.vouchers has a trigger audit_voucher_change that is not this migration''s (%)', v; end if;
  v_trg_v_new := v is null;
  select pg_get_triggerdef(t.oid) into v from pg_trigger t
   where t.tgrelid = 'public.voucher_store_prices'::regclass and t.tgname = 'audit_voucher_store_price_change' and not t.tgisinternal;
  if v is not null and v <> c_trg_vp then
    raise exception '423: public.voucher_store_prices has a trigger audit_voucher_store_price_change that is not this migration''s (%)', v; end if;
  v_trg_vp_new := v is null;
  if v_trg_v_new <> v_trg_vp_new or v_trg_v_new <> (to_regprocedure('public.trg_audit_voucher_change()') is null) then
    raise exception '423: only part of the voucher audit is installed; re-read and re-test'; end if;
  select string_agg(t.tgrelid::regclass::text || '.' || t.tgname, ', ') into v
    from pg_trigger t join pg_proc p on p.oid = t.tgfoid
   where t.tgrelid in ('public.vouchers'::regclass, 'public.voucher_store_prices'::regclass)
     and not t.tgisinternal and t.tgname not in ('audit_voucher_change', 'audit_voucher_store_price_change')
     and (p.proname = 'trg_audit_voucher_change' or p.prosrc ~* 'audit_logs|write_audit');
  if v is not null then
    raise exception '423: another trigger already writes the audit log for vouchers (%); re-read and re-test', v; end if;
  if exists (select 1 from pg_trigger t where t.tgrelid in ('public.vouchers'::regclass, 'public.voucher_store_prices'::regclass)
              and not t.tgisinternal and t.tgenabled <> 'O') then
    raise exception '423: a trigger on vouchers or voucher_store_prices is disabled'; end if;
  -- The request id columns: missing, or exactly this migration's.
  for r in select * from (values
    ('public.credit_package_split_groups', c_ix_cp, v_cp_mode), ('public.premium_bundle_split_groups', c_ix_pb, v_pb_mode)) x(tbl, ix, mode)
  loop
    select format_type(a.atttypid, a.atttypmod) || case when a.attnotnull then ' not null' else '' end into v
      from pg_attribute a where a.attrelid = r.tbl::regclass and a.attname = 'request_id' and not a.attisdropped;
    if v is not null and v <> 'uuid' then
      raise exception '423: %.request_id exists and is not a nullable uuid (%)', r.tbl, v; end if;
    if (v is null) <> (r.mode = 'build') then
      raise exception '423: %.request_id and the split function are not both old or both new; re-read and re-test', r.tbl; end if;
    if v is not null and not exists (select 1 from pg_indexes x where (x.schemaname || '.' || x.tablename) = r.tbl
                                       and x.indexdef = r.ix) then
      raise exception '423: %.request_id has no unique index as this migration makes it', r.tbl; end if;
  end loop;
  -- The price check: missing, or exactly this one (validated).
  select pg_get_constraintdef(c.oid) || case when c.convalidated then '' else ' NOT VALID' end into v
    from pg_constraint c where c.conrelid = 'public.unlimited_therapy_store_prices'::regclass and c.conname = c_chk_name;
  if v is not null and v <> c_chk_def then
    raise exception '423: % exists and is not this migration''s (%)', c_chk_name, v; end if;
  v_chk_new := v is null;
  if exists (select 1 from pg_constraint c where c.conrelid = 'public.unlimited_therapy_store_prices'::regclass
              and c.contype = 'c' and c.conname <> c_chk_name) then
    raise exception '423: public.unlimited_therapy_store_prices has a check it did not have on 9 Oct 2026'; end if;

  -- The grants of the functions changed in place, to compare after.
  select array_agg(p.oid::regprocedure::text || '=' || coalesce(p.proacl::text, '') order by p.oid::regprocedure::text)
    into v_acl
    from pg_proc p
   where p.pronamespace = 'public'::regnamespace
     and p.oid::regprocedure::text in (
       'set_voucher_price_all_stores(uuid,numeric,boolean)', 'set_voucher_prices(uuid,uuid,numeric,numeric,boolean)',
       'upsert_therapy_service(uuid,text,text,numeric,integer,text,integer,numeric,text,boolean,text)',
       'upsert_therapy_closure_date(uuid,date,text,text,text,text,date,text,text,text)',
       'set_unlimited_therapy_price(uuid,uuid,numeric,numeric,boolean)');
  -- The split functions are the API's for signed-in logins and the service role.
  foreach v in array array[c_cp_old, c_pb_old] loop
    if to_regprocedure('public.' || v) is not null
       and (has_function_privilege('anon', 'public.' || v, 'execute')
            or not has_function_privilege('authenticated', 'public.' || v, 'execute')
            or not has_function_privilege('service_role', 'public.' || v, 'execute')) then
      raise exception '423: public.% is not granted as read on 9 Oct 2026', v; end if;
  end loop;

  -- ── Change ───────────────────────────────────────────────────────────────
  if v_cp_mode = 'build' then
    alter table public.credit_package_split_groups add column request_id uuid;
    comment on column public.credit_package_split_groups.request_id is
      '423: the id the split panel sent; the same id again returns this group instead of making another.';
    create unique index credit_package_split_groups_request_id_key
      on public.credit_package_split_groups (request_id) where request_id is not null;
  end if;
  if v_pb_mode = 'build' then
    alter table public.premium_bundle_split_groups add column request_id uuid;
    comment on column public.premium_bundle_split_groups.request_id is
      '423: the id the split panel sent; the same id again returns this group instead of making another.';
    create unique index premium_bundle_split_groups_request_id_key
      on public.premium_bundle_split_groups (request_id) where request_id is not null;
  end if;
  if v_chk_new then
    alter table public.unlimited_therapy_store_prices
      add constraint unlimited_therapy_store_prices_selling_price_check
      check (selling_price is null or (selling_price >= 0 and selling_price <> 'NaN'::numeric)) not valid;
    alter table public.unlimited_therapy_store_prices
      validate constraint unlimited_therapy_store_prices_selling_price_check;
  end if;

  for i in 1 .. coalesce(array_length(v_fns, 1), 0) loop
    execute v_defs[i];
    if v_fns[i] = 'trg_audit_voucher_change()' then
      execute 'revoke all on function public.trg_audit_voucher_change() from public, anon, authenticated';
      execute 'grant execute on function public.trg_audit_voucher_change() to service_role';
    elsif v_fns[i] in ('soft_delete_voucher(uuid,text,boolean)', 'set_therapy_service_stores(uuid,jsonb)', c_cp_new, c_pb_new) then
      execute format('revoke all on function public.%s from public, anon', v_fns[i]);
      execute format('grant execute on function public.%s to authenticated, service_role', v_fns[i]);
    end if;
  end loop;
  if v_cp_mode = 'build' then
    execute 'drop function public.' || c_cp_old;
  end if;
  if v_pb_mode = 'build' then
    execute 'drop function public.' || c_pb_old;
  end if;
  if v_trg_v_new then
    create trigger audit_voucher_change
      after insert or update or delete on public.vouchers
      for each row execute function public.trg_audit_voucher_change();
  end if;
  if v_trg_vp_new then
    create trigger audit_voucher_store_price_change
      after insert or update or delete on public.voucher_store_prices
      for each row execute function public.trg_audit_voucher_change();
  end if;

  -- ── Installed exactly as tested ───────────────────────────────────────────
  v_bad := null;
  for r in select * from (values
    ('trg_audit_voucher_change()', c_audit_after), ('soft_delete_voucher(uuid,text,boolean)', c_softdel_after),
    ('set_therapy_service_stores(uuid,jsonb)', c_stores_after),
    ('set_voucher_price_all_stores(uuid,numeric,boolean)', c_vpall_after),
    ('set_voucher_prices(uuid,uuid,numeric,numeric,boolean)', c_vp_after),
    ('upsert_therapy_service(uuid,text,text,numeric,integer,text,integer,numeric,text,boolean,text)', c_svc_after),
    ('upsert_therapy_closure_date(uuid,date,text,text,text,text,date,text,text,text)', c_cl_after),
    ('set_unlimited_therapy_price(uuid,uuid,numeric,numeric,boolean)', c_ut_after),
    (c_cp_new, c_cp_after), (c_pb_new, c_pb_after)) x(fn, after_md5)
  loop
    v := md5(pg_get_functiondef(to_regprocedure('public.' || r.fn)));
    if v is distinct from r.after_md5 then
      v_bad := concat_ws('; ', v_bad, r.fn || ' ' || coalesce(v, 'missing')); end if;
  end loop;
  if v_bad is not null then
    raise exception '423: installed with md5s other than the tested ones: %', v_bad; end if;
  if to_regprocedure('public.' || c_cp_old) is not null or to_regprocedure('public.' || c_pb_old) is not null then
    raise exception '423: an old six-argument split function is still there'; end if;
  select pg_get_triggerdef(t.oid) into v from pg_trigger t
   where t.tgrelid = 'public.vouchers'::regclass and t.tgname = 'audit_voucher_change' and t.tgenabled = 'O';
  if v is distinct from c_trg_v then
    raise exception '423: the audit trigger on public.vouchers is not as tested (%)', v; end if;
  select pg_get_triggerdef(t.oid) into v from pg_trigger t
   where t.tgrelid = 'public.voucher_store_prices'::regclass and t.tgname = 'audit_voucher_store_price_change' and t.tgenabled = 'O';
  if v is distinct from c_trg_vp then
    raise exception '423: the audit trigger on public.voucher_store_prices is not as tested (%)', v; end if;
  if not exists (select 1 from pg_indexes x where x.schemaname = 'public' and x.indexdef = c_ix_cp)
     or not exists (select 1 from pg_indexes x where x.schemaname = 'public' and x.indexdef = c_ix_pb) then
    raise exception '423: a request id index is not as tested'; end if;
  if not exists (select 1 from pg_constraint c where c.conrelid = 'public.unlimited_therapy_store_prices'::regclass
                  and c.conname = c_chk_name and c.convalidated and pg_get_constraintdef(c.oid) = c_chk_def) then
    raise exception '423: the price check is not there, validated, as tested'; end if;

  -- ── Grants, by the catalogue ─────────────────────────────────────────────
  if (select array_agg(p.oid::regprocedure::text || '=' || coalesce(p.proacl::text, '') order by p.oid::regprocedure::text)
        from pg_proc p
       where p.pronamespace = 'public'::regnamespace
         and p.oid::regprocedure::text in (
           'set_voucher_price_all_stores(uuid,numeric,boolean)', 'set_voucher_prices(uuid,uuid,numeric,numeric,boolean)',
           'upsert_therapy_service(uuid,text,text,numeric,integer,text,integer,numeric,text,boolean,text)',
           'upsert_therapy_closure_date(uuid,date,text,text,text,text,date,text,text,text)',
           'set_unlimited_therapy_price(uuid,uuid,numeric,numeric,boolean)'))
     is distinct from v_acl then
    raise exception '423: the grants of the changed functions changed'; end if;
  foreach v in array array['soft_delete_voucher(uuid,text,boolean)', 'set_therapy_service_stores(uuid,jsonb)', c_cp_new, c_pb_new] loop
    if has_function_privilege('anon', 'public.' || v, 'execute')
       or not has_function_privilege('authenticated', 'public.' || v, 'execute')
       or not has_function_privilege('service_role', 'public.' || v, 'execute')
       or exists (select 1 from pg_proc p, aclexplode(p.proacl) a
                   where p.oid = to_regprocedure('public.' || v) and a.grantee = 0) then
      raise exception '423: public.% is not granted to signed-in logins and the service role alone', v; end if;
  end loop;
  if has_function_privilege('anon', 'public.trg_audit_voucher_change()', 'execute')
     or has_function_privilege('authenticated', 'public.trg_audit_voucher_change()', 'execute')
     or not has_function_privilege('service_role', 'public.trg_audit_voucher_change()', 'execute') then
    raise exception '423: public.trg_audit_voucher_change() is not the service role''s alone'; end if;

  -- ── Behaviour, switching role (nothing is printed, no row remains) ───────
  -- A signed-in login with no profile, and the anon key.
  foreach v in array array['authenticated', 'anon'] loop
    perform set_config('request.jwt.claims', json_build_object('sub', gen_random_uuid(), 'role', v)::text, true);
    execute format('set local role %I', v);
    begin
      perform public.soft_delete_voucher(gen_random_uuid(), null, false);
      raise exception '423: % may call soft_delete_voucher', v;
    exception when insufficient_privilege then null;
    end;
    begin
      perform public.set_therapy_service_stores(gen_random_uuid(), '[]'::jsonb);
      raise exception '423: % may call set_therapy_service_stores', v;
    exception when insufficient_privilege then null;
    end;
    begin
      perform public.create_split_credit_package_invoices(gen_random_uuid(), gen_random_uuid(), '[]'::jsonb, null, null, null, gen_random_uuid());
      raise exception '423: % may call create_split_credit_package_invoices', v;
    exception when insufficient_privilege then null;
    end;
    execute 'reset role';
  end loop;
  perform set_config('request.jwt.claims', '', true);

  -- Rules 1-8 once each, inside a block that is always undone: a made-up
  -- Owner and member of staff (@sig.invalid), a store, two vouchers, a
  -- therapy service and package, a credit package and a bundle.
  begin
    insert into auth.users (id, email) values (gen_random_uuid(), '423-check-owner-' || gen_random_uuid() || '@sig.invalid')
      returning id into v_owner;
    insert into auth.users (id, email) values (gen_random_uuid(), '423-check-staff-' || gen_random_uuid() || '@sig.invalid')
      returning id into v_staff;
    insert into public.profiles (id, full_name, email, role, is_active)
    select u.id, '423 check', u.email, x.role::public.user_role, true
      from auth.users u join (values (v_owner, 'owner'), (v_staff, 'staff')) x(id, role) on x.id = u.id;
    insert into public.stores (name, code) values ('423 check A', '423CHKA-' || substr(md5(random()::text), 1, 6))
      returning id into v_store;
    insert into public.stores (name, code) values ('423 check B', '423CHKB-' || substr(md5(random()::text), 1, 6))
      returning id into v_store2;

    perform set_config('request.jwt.claims', json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    -- Rule 1: made and changed through the table, as the page does.
    insert into public.vouchers (name, code, voucher_kind, selling_price)
    values ('423 check voucher', '423CHK1', 'normal', 10) returning id into v_v1;
    insert into public.vouchers (name, code, voucher_kind, selling_price)
    values ('423 check voucher 2', '423CHK2', 'normal', 10) returning id into v_v2;
    update public.vouchers set name = '423 check voucher one' where id = v_v1;
    update public.vouchers set is_active = is_active where id = v_v1;  -- nothing changes: no row
    execute 'reset role';
    if (select count(*) from public.audit_logs a where a.record_id = v_v1 and a.table_name = 'vouchers') <> 2
       or not exists (select 1 from public.audit_logs a where a.record_id = v_v1 and a.action = 'voucher_created'
                       and a.changed_by = v_owner and a.actor_role = 'owner' and a.module = 'catalogue')
       or not exists (select 1 from public.audit_logs a where a.record_id = v_v1 and a.action = 'voucher_updated'
                       and a.old_data = jsonb_build_object('name', '423 check voucher')
                       and a.new_data = jsonb_build_object('name', '423 check voucher one')) then
      raise exception '423: a voucher made and changed is not in the audit log as tested'; end if;

    -- Rule 2: stock at a store asks first; staff are refused; then deleted.
    insert into public.voucher_store_stock (voucher_id, store_id, current_qty) values (v_v1, v_store, 3);
    perform set_config('request.jwt.claims', json_build_object('sub', v_staff, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    begin
      perform public.soft_delete_voucher(v_v1, null, true);
      raise exception '423: a member of staff may delete a voucher';
    exception when insufficient_privilege then null;
    end;
    perform set_config('request.jwt.claims', json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);
    v_res := public.soft_delete_voucher(v_v1, ' End of the event ', false);
    if not (v_res ->> 'needs_confirmation')::boolean or (v_res ->> 'deleted')::boolean
       or (v_res ->> 'store_stock_total')::int <> 3 or (v_res ->> 'holders_units')::int <> 0 then
      raise exception '423: a voucher still in stock did not ask first (%)', v_res; end if;
    v_res := public.soft_delete_voucher(v_v1, ' End of the event ', true);
    execute 'reset role';
    if not (v_res ->> 'deleted')::boolean
       or (select deleted_at is null or is_active from public.vouchers where id = v_v1)
       or not exists (select 1 from public.audit_logs a where a.record_id = v_v1 and a.action = 'voucher_deleted'
                       and a.reason = 'End of the event' and a.changed_by = v_owner
                       and (a.new_data -> 'detail' ->> 'store_stock_total')::int = 3) then
      raise exception '423: a confirmed delete is not as tested (%)', v_res; end if;
    if coalesce(current_setting('energia.voucher_change_reason', true), '') <> ''
       or coalesce(current_setting('energia.voucher_change_detail', true), '') <> '' then
      raise exception '423: the delete left its reason set for the rest of the transaction'; end if;

    -- Rule 3: one price everywhere keeps a store switched off (null), and
    -- the audit has the price rows under the voucher: one before-and-after
    -- row per store changed, and no "voucher prices set" summary.
    insert into public.voucher_store_prices (voucher_id, store_id, selling_price, available_at_store)
    values (v_v2, v_store, 10, false);
    perform set_config('request.jwt.claims', json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    perform public.set_voucher_price_all_stores(v_v2, 12, null);
    perform public.set_voucher_prices(v_v2, v_store, 12, 12, false);  -- the same again: no row
    execute 'reset role';
    if (select selling_price <> 12 or available_at_store from public.voucher_store_prices
         where voucher_id = v_v2 and store_id = v_store)
       or (select selling_price <> 12 or not available_at_store from public.voucher_store_prices
            where voucher_id = v_v2 and store_id = v_store2)
       or not exists (select 1 from public.audit_logs a where a.record_id = v_v2 and a.store_id = v_store
                       and a.action = 'voucher_store_price_updated' and a.module = 'pricing'
                       and a.changed_by = v_owner
                       and a.old_data = jsonb_build_object('selling_price', 10)
                       and a.new_data = jsonb_build_object('selling_price', 12, 'store_id', v_store,
                                                           'price_row_id', a.new_data ->> 'price_row_id')) then
      raise exception '423: one price everywhere did not keep each store''s availability, or was not audited'; end if;
    -- Store A: the row made above and the one change; store B: the row made.
    if (select count(*) from public.audit_logs a where a.record_id = v_v2 and a.store_id = v_store) <> 2
       or (select count(*) from public.audit_logs a where a.record_id = v_v2 and a.store_id = v_store2) <> 1
       or exists (select 1 from public.audit_logs a where a.record_id = v_v2 and a.action = 'voucher_prices_set') then
      raise exception '423: a voucher price change did not leave exactly one before-and-after row per store'; end if;

    -- Rules 4 and 5: notes kept; stores saved together or not at all.
    insert into public.therapy_services (service_code, name, standard_price, duration_minutes, is_active, notes)
    values ('423chk-' || substr(md5(random()::text), 1, 6), '423 check service', 50, 30, true, 'Kept note')
    returning id into v_svc;
    perform set_config('request.jwt.claims', json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    perform public.upsert_therapy_service(v_svc, '423chk-svc', '423 check service', 55, 30, 'unrestricted', 1, null, null, true, null);
    if (select notes from public.therapy_services where id = v_svc) is distinct from 'Kept note' then
      raise exception '423: saving a service with no notes wiped them'; end if;
    perform public.upsert_therapy_service(v_svc, '423chk-svc', '423 check service', 55, 30, 'unrestricted', 1, null, null, true, '');
    if (select notes from public.therapy_services where id = v_svc) is not null then
      raise exception '423: an empty note did not clear the notes'; end if;
    begin
      perform public.set_therapy_service_stores(v_svc, jsonb_build_array(
        jsonb_build_object('store_id', v_store, 'is_available', true, 'price_override', 60),
        jsonb_build_object('store_id', v_store2, 'is_available', true, 'price_override', -1)));
      raise exception '423: a negative service price was saved';
    exception when raise_exception then
      if sqlerrm not like 'The price at 423 check B cannot be negative%' then raise; end if;
    end;
    if exists (select 1 from public.therapy_service_stores where service_id = v_svc) then
      raise exception '423: a store save that failed left some stores saved'; end if;
    n := public.set_therapy_service_stores(v_svc, jsonb_build_array(
           jsonb_build_object('store_id', v_store, 'is_available', true, 'price_override', 60),
           jsonb_build_object('store_id', v_store2, 'is_available', false, 'price_override', null)));
    k := (select count(*) from public.therapy_service_stores where service_id = v_svc);
    if n <> 2 or k <> 2 then
      raise exception '423: the stores of a service were not saved together (% sent, % saved)', n, k; end if;

    -- Rule 7: a region is trimmed, and needs a country.
    begin
      perform public.upsert_therapy_closure_date(null, date '2099-01-02', 'company_closure', '423 check', null, 'North', null, null, null, null);
      raise exception '423: a region with no country was saved';
    exception when raise_exception then
      if sqlerrm not like 'Choose the country this region belongs to%' then raise; end if;
    end;
    execute 'reset role';
    insert into public.therapy_holiday_countries (code, name, is_active) values ('ZZ', '423 check', true)
      on conflict (code) do nothing;
    execute 'set local role authenticated';
    v_cl := public.upsert_therapy_closure_date(null, date '2099-01-02', 'company_closure', '423 check', 'ZZ', '   ', null, null, null, null);
    if (select region from public.therapy_closure_dates where id = v_cl) is not null then
      raise exception '423: a blank region was stored'; end if;

    -- Rule 8: a therapy price below zero, or NaN, is refused, by the function and by the table.
    execute 'reset role';
    insert into public.unlimited_therapy_packages (name, duration_months) values ('423 check package', 12)
      returning id into v_pkg;
    execute 'set local role authenticated';
    begin
      perform public.set_unlimited_therapy_price(v_pkg, v_store, -5, -5, true);
      raise exception '423: a negative therapy price was saved';
    exception when raise_exception then
      if sqlerrm not like 'Price cannot be negative%' then raise; end if;
    end;
    perform public.set_unlimited_therapy_price(v_pkg, v_store, 0, 0, true);
    execute 'reset role';
    begin
      insert into public.unlimited_therapy_store_prices (package_id, store_id, selling_price) values (v_pkg, v_store2, -1);
      raise exception '423: the table took a negative therapy price';
    exception when check_violation then null;
    end;
    begin
      insert into public.unlimited_therapy_store_prices (package_id, store_id, selling_price) values (v_pkg, v_store2, 'NaN');
      raise exception '423: the table took NaN as a therapy price';
    exception when check_violation then null;
    end;

    -- Rule 6: a split group made with a request id is returned again, and the
    -- id cannot be used for another package or bundle, or for other
    -- customers. (No invoice is made here; the test suite makes real ones.)
    insert into public.credit_packages (name, customer_price, paid_credit_amount, is_active)
    values ('423 check credit', 100, 100, true) returning id into v_cpk;
    insert into public.credit_packages (name, customer_price, paid_credit_amount, is_active)
    values ('423 check credit 2', 100, 100, true) returning id into v_cpk2;
    v_req := gen_random_uuid();
    insert into public.credit_package_split_groups (store_id, credit_package_id, package_name_snapshot, package_price_snapshot,
      paid_credit_total_snapshot, bonus_credit_total_snapshot, reward_voucher_total_snapshot, customer_count, created_by, request_id)
    values (v_store, v_cpk, '423 check credit', 100, 100, 0, 0, 2, v_owner, v_req) returning id into v_grp;
    perform set_config('request.jwt.claims', json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    v_res := public.create_split_credit_package_invoices(v_store, v_cpk, '[]'::jsonb, null, null, null, v_req);
    if not coalesce((v_res ->> 'replayed')::boolean, false) or (v_res ->> 'split_group_id')::uuid <> v_grp
       or v_res -> 'invoices' <> '[]'::jsonb then
      raise exception '423: a credit package split sent again was not returned (%)', v_res; end if;
    begin
      perform public.create_split_credit_package_invoices(v_store, v_cpk2, '[]'::jsonb, null, null, null, v_req);
      raise exception '423: a request id was taken for another package';
    exception when raise_exception then
      if sqlerrm not like 'This request was already used for another sale%' then raise; end if;
    end;
    begin
      perform public.create_split_credit_package_invoices(v_store, v_cpk,
        jsonb_build_array(jsonb_build_object('customer_id', v_owner, 'payment_amount', 100)), null, null, null, v_req);
      raise exception '423: a request id was taken for other customers';
    exception when raise_exception then
      if sqlerrm not like 'This request was already used for another sale%' then raise; end if;
    end;
    execute 'reset role';
    insert into public.premium_bundles (name, customer_payment_amount, paid_credit_amount, bonus_credit_amount, free_voucher_qty, is_active)
    values ('423 check bundle', 100, 100, 0, 0, true) returning id into v_pbk;
    insert into public.premium_bundles (name, customer_payment_amount, paid_credit_amount, bonus_credit_amount, free_voucher_qty, is_active)
    values ('423 check bundle 2', 100, 100, 0, 0, true) returning id into v_pbk2;
    v_req := gen_random_uuid();
    insert into public.premium_bundle_split_groups (store_id, premium_bundle_id, bundle_name_snapshot, payment_snapshot,
      paid_credit_total_snapshot, bonus_credit_total_snapshot, free_voucher_total_snapshot, customer_count, created_by, request_id)
    values (v_store, v_pbk, '423 check bundle', 100, 100, 0, 0, 2, v_owner, v_req) returning id into v_grp;
    perform set_config('request.jwt.claims', json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    v_res := public.create_split_premium_bundle_invoices(v_store, v_pbk, '[]'::jsonb, null, null, null, v_req);
    if not coalesce((v_res ->> 'replayed')::boolean, false) or (v_res ->> 'split_group_id')::uuid <> v_grp then
      raise exception '423: a premium bundle split sent again was not returned (%)', v_res; end if;
    begin
      perform public.create_split_premium_bundle_invoices(v_store, v_pbk2, '[]'::jsonb, null, null, null, v_req);
      raise exception '423: a request id was taken for another bundle';
    exception when raise_exception then
      if sqlerrm not like 'This request was already used for another sale%' then raise; end if;
    end;
    begin
      perform public.create_split_premium_bundle_invoices(v_store, v_pbk,
        jsonb_build_array(jsonb_build_object('customer_id', v_owner, 'payment_amount', 100)), null, null, null, v_req);
      raise exception '423: a request id was taken for other customers';
    exception when raise_exception then
      if sqlerrm not like 'This request was already used for another sale%' then raise; end if;
    end;
    execute 'reset role';

    raise exception using errcode = 'P0423', message = '423: check done, undone';
  exception when sqlstate 'P0423' then null;
  end;
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);

  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $mig$;
