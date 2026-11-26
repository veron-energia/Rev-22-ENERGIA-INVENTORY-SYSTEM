-- 541_lows_upload_rules_staff_test_send_log_loans_tiktok_prices.sql
--
-- PICTURES ONLY, AND NO SVG, IN THE TWO UPLOAD BUCKETS; ONE ACTIVE-STAFF TEST EVERYWHERE; A SEND
-- IS LOGGED AGAINST A DOCUMENT THE CALLER CAN SEE; A LOAN COMES BACK WHERE IT WAS LENT FROM; A
-- TIKTOK FILE HAS AT MOST 20,000 ROWS; A PRICE CHANGE LOGS THE OLD PRICE
--
--   From the security audit of 17 Nov 2026 (Low findings L13, L14, L16 and L19). The BEFORE md5s
--   and the relied-on md5s below are those of production after 540 (head 20261125171841, function
--   fingerprint 18fcffcae0f51cc09245231c3779585e/1462; 540's AFTER md5s are this file's BEFORE md5s
--   where 540 changed a function). If production differs when this is applied, it refuses and
--   changes nothing. It needs 540.
--   (The number 541 is this file's name and its errors' prefix; if it changes at commit, change it
--   there, in the 541 comments it writes into the functions below (and so their AFTER md5s, also in
--   scripts/permissions/undo-541.sql and in the suites that know them), and in the name and path
--   of its suite.)
--
-- GO-LIVE: any time after 540; no page needs to change first. The pages work before and after it
--   (the send log is written best effort and only warns; the take-back form already starts on the
--   loan's own place; the TikTok page never sends more than 20,000 rows). The page side of L13
--   (the store pictures' and survey attachments' own checks) is separate and works on both.
--
-- WHAT WAS WRONG
--
--   L13. store-assets is a public bucket with no size or type limit; survey-attachments takes any
--     image/* type, SVG (which can carry script) included.
--   L14. Twelve signed-in functions test "active staff" their own older way, which does not ask
--     for an accepted invitation (and two, set_product_important and my_assigned_stores, do not ask
--     for deleted_at either). Pending invitees are inactive, so in practice nobody got through.
--   L16. record_document_send writes whatever document number, document and customer a browser
--     sends, for any document, so the send log can say a document was sent that never was.
--   L19. return_stock_loan takes a return into any active store; stage_tiktok_orders takes any
--     number of rows; set_product_prices logs the new price only.
--
-- THE RULES
--
--   * L13 (the audit's fix): store-assets takes PNG, JPEG and WebP up to 5 MB. survey-attachments'
--     pictures are an explicit list, JPEG, PNG, GIF, WebP, HEIC and HEIF, so no SVG; its document
--     types and its 10 MB limit are as they were. invoice-pdfs is not touched. Both lists are
--     exactly the pages' own (src/lib/storeAssetRules.mjs, src/lib/survey/attachmentRules.mjs).
--     The limits act on new uploads only. Production holds 14 files in store-assets, PNG or JPEG,
--     the largest 1.19 MB, and 413 in survey-attachments, PDF, DOCX and PNG, no SVG: each is
--     inside its new rule.
--   * L14 (the audit's fix): require_active_staff() is the test, as in every function since 406.
--     The practical effect is nil, so each function otherwise answers as before.
--   * L16 (the audit's fix): look the document up, refuse a caller who cannot see it, and take the
--     number and the customer from the document.
--   * L19, loans (the user, 26 Nov 2026): a loan comes back only into its OWN location (its
--     location_type and its store or warehouse). An Owner or a Manager may still name another
--     active store, or a warehouse they hold the warehouse stock permission for; the retired Admin
--     role is on the Staff side, as on the other Owner-level routes since 539. The loan's event
--     row already records where each return went. THIS REPLACES THE RULE OF 6 OCT 2026 in 401's
--     header ("where it came back to, any active store"). Production holds 2 loans and 1 return,
--     which went back to its own location.
--   * L19, TikTok: the server takes at most 20,000 rows a call, the page's own limit for a sheet
--     (MAX_IMPORT_ROWS, per sheet, src/lib/tiktok/readSpreadsheet.mjs), for order files and for
--     settlement files alike. The page sends one file's rows in one call (TikTokImportPage.tsx,
--     handleUpload), after dropping the header and empty rows; a settlement file's Withdrawal
--     records come from one other sheet of it (src/lib/tiktok/withdrawals.mjs) and go in the same
--     call. So a file the page accepts is never refused here.
--   * L19, prices: each change log entry of set_product_prices carries the old price beside the
--     new one.
--   * L19, a Manager and other stores' staff: KEPT BY DECISION. The user decided (rule R2) that a
--     Manager manages staff company-wide; every change to a profile is recorded since 532. The
--     "update profiles" rule is not touched here.
--
-- WHAT THIS DOES (every new refusal is errcode 42501 unless said otherwise)
--
--   * storage.buckets: store-assets gets file_size_limit 5242880 and allowed_mime_types
--     {image/png,image/jpeg,image/webp}; survey-attachments' allowed_mime_types becomes
--     {image/jpeg,image/png,image/gif,image/webp,image/heic,image/heif} followed by its seven
--     document types exactly as before. It refuses if a file already in either bucket falls
--     outside its new rule. Storage refuses a new upload outside the rule; files already there
--     stay.
--   * L14, in place of each older test, as its first refusal (each function otherwise word for
--     word as before):
--       refusing functions: require_active_staff(); a login that is not active staff now hears
--       406's sentence ("Only active Energia staff can do this.") instead of the function's own.
--       Where it lets the caller by without a login (it returns no role), the same test is made
--       of the claimed user (current_user_role(), which 406 defines exactly as
--       require_active_staff() tests): so the secret key and the server's own work are still
--       refused with the function's own sentence, and a server function running with an active
--       staff member's claims still passes, both as before:
--         affiliate_portal_login, unlink_affiliate_account (then an Owner only),
--         tiktok_bank_payouts, tiktok_xero_payouts (then an Owner or a Manager),
--         stock_history_options (then the five staff roles),
--         customer_match_candidates, record_invoice_handover, record_invoice_settlement,
--         affiliate_staff_directory (it already called require_active_staff(); the older test after
--         it goes), set_product_important (its role now comes from require_active_staff(), so it
--         asks for deleted_at too);
--       two functions that answer rather than refuse: the same test through current_user_role()
--       (406 defines it exactly as require_active_staff() tests), so they still answer "no" with no
--       error, as they did: staff_may_correct_invoice (false), my_assigned_stores (no stores; it
--       now asks for deleted_at too). require_active_staff() would turn that answer into an error,
--       and staff_may_correct_invoice runs inside correct_invoice, correct_invoice_payment_methods,
--       update_invoice_internal, create_staff_transfer_request and the trigger
--       trg_lock_invoice_payments.
--   * L16, record_document_send: after 540's guard and require_active_staff(), it reads the
--     document by p_doc_id and p_doc_kind: an invoice not deleted and of a store the caller has
--     access to (user_has_store_access, as record_document_printed); a special sale or a rental the
--     caller may read (a Manager and up, or access to its store or to the store it came from, as
--     their read rules). Anything else, a missing document or no p_doc_id: "That document is not
--     one you can see." An unknown kind: "Unknown document kind" (22023). The row's doc_no and
--     customer_id are the document's; p_doc_no and p_customer_id are no longer read (the page
--     sends the same values). The channel, address, PDF path, status and error text are the
--     caller's, as before (the PDF path is checked by withdraw_document_link, 523).
--   * L19, return_stock_loan: before its existing place checks, a "returned" entry that names a
--     place other than the loan's own is refused unless the caller is an Owner or a Manager:
--     "LOAN-… was lent from <place>, so it comes back there. Only an Owner or a Manager can take it
--     back into another store or warehouse." (an Admin, Staff and the secret key are refused; an
--     Inventory Manager is refused first by 540's guard, which stays the first statement). The
--     checks after it are as before (an active store; a warehouse with the warehouse stock
--     permission). Its header comment says the new rule. lend_stock is not changed.
--   * L19, stage_tiktok_orders and stage_tiktok_settlement (the settled lines; callable on its own
--     too): after the access check and "No rows to import", more than 20,000 rows: "A TikTok file
--     has at most 20,000 rows. Please export a shorter date range and try again." (54000), with
--     nothing written. stage_tiktok_settlement_file (what the page calls for a settlement file):
--     the access check first (tiktok_access_check, as stage_tiktok_settlement makes it), then more
--     than 20,000 Withdrawal records: "A TikTok file's Withdrawal records have at most 20,000 rows.
--     ..." (54000), before anything is staged; then as before.
--   * L19, set_product_prices: it reads (and locks) the store's row for the product before writing,
--     and its Audit Log entry product_prices_set carries old_data {store, price} (and removed: true
--     when the price had been taken off the list), or none when the store had no price for it.
--   * Every function this replaces gets search_path public, pg_temp (it was public).
--
-- WHAT STAYS
--
--   * invoice-pdfs, and the files already in the two buckets.
--   * Who may do what in the twelve L14 functions, and every answer they give to active staff.
--   * The send log's read rule (any staff role but an Inventory Manager, 540): reading it is as
--     before. The audit's "read by all staff" part is not changed here.
--   * Loans: who may take a loan back at all (stock_loan_access, 540's guard), the quantities, the
--     outcomes, the replay of a repeated form. A Staff member can still pick another store on the
--     take-back form; the server now refuses it.
--   * Prices: who may set them (is_owner_or_manager, company-wide, R2), the upsert, the new value.
--   * A Manager's company-wide user management (R2, kept by decision).
--   * The other functions keep search_path public until 543 moves them.
--
-- UNDO
--
--   scripts/permissions/undo-541.sql (it refuses unless every function and bucket here is exactly
--   541's): takes 541's text out of the 18 functions, putting each back exactly as before (md5s
--   below), and puts the two buckets' rules back. Run it BEFORE scripts/customers/undo-540.sql
--   (that undo pins 540's AFTER md5s, which 541 changes in six functions). A later migration
--   changing any of these must pin 541's AFTER md5.
--
-- NO SELF-TEST INSIDE; the suite is scripts/permissions/tests/security-lows-541.sql.
--
-- One transaction with its history row, by the usual wrapper; nothing else is written.

do $mig$
declare
  -- Functions 541 relies on, as tested: the role and staff tests, store access, the audit writer,
  -- 540's guard, the loan and TikTok access checks.
  c_relied constant text[] := array[
    'current_user_role()',
    'require_active_staff(text[])',
    'user_has_store_access(uuid)',
    'is_manager_or_above()',
    'is_owner_or_manager()',
    'can_manage_warehouse_stock()',
    'write_audit_ex(text,uuid,text,jsonb,jsonb,text,text,uuid,text,text)',
    'inventory_manager_guard(text)',
    'stock_loan_access(text,uuid,boolean)',
    'tiktok_access_check(uuid)'];
  c_relied_md5 constant text[] := array[
    '519b0a33a3548f970c5d585b6e76a389',
    '877b3aa74cea559881979bb161c450e2',
    '708992afaa6c3951f6329239b742987c',
    'e87f6da4a7284374f0e2bc5b55c502be',
    'a98e50f1b6d3fa1e6c62cf52a8073cc8',
    '0fa45b2379faaf6c32ab5429b5b0792b',
    'c705c733e213a27f0dc32d54322cc855',
    '6a2c8611ef58a1e6cdf4a91a0c662c9e',
    '09f68356afdabb88cade05af7859e158',
    '85e207b126a3296ccfdb12f27d46faae'];
  -- The functions patched: BEFORE, AFTER; grants unchanged (all: authenticated, postgres,
  -- service_role).
  c_sig constant text[] := array[
    'affiliate_portal_login(uuid)',
    'affiliate_staff_directory(text,integer,integer)',
    'customer_match_candidates(text,text)',
    'my_assigned_stores()',
    'record_invoice_handover(uuid,jsonb,uuid)',
    'record_invoice_settlement(uuid,jsonb,uuid)',
    'set_product_important(uuid,boolean)',
    'staff_may_correct_invoice(uuid)',
    'stock_history_options(text,text,integer)',
    'tiktok_bank_payouts(date,date)',
    'tiktok_xero_payouts(integer,integer)',
    'unlink_affiliate_account(uuid,text)',
    'record_document_send(text,text,text,uuid,uuid,text,text,text,text)',
    'return_stock_loan(uuid,jsonb,text,uuid)',
    'stage_tiktok_orders(uuid,text,text,jsonb)',
    'set_product_prices(uuid,uuid,numeric,numeric,text)',
    'stage_tiktok_settlement(uuid,text,text,jsonb)',
    'stage_tiktok_settlement_file(uuid,text,text,jsonb,jsonb)'];
  c_before constant text[] := array[
    '7639d70c457c3c60cd41780118a6e320',
    '61595fb38791f91eecdeb0d51763fce3',
    'f38e1bc8b137d362da3830230442f46a',
    '9aea3b976867b849e4c879dd5151d84b',
    'a21a19711bdc521c09c8b5c967c6d77b',
    '74b29c82e1717695dacbf3768f34c588',
    '5962420ad202cecb61743e6ed4087b31',
    '60cbe4859f1f1f43da02115c019fc4bf',
    '0e70e3887d37fda49f27c0e74717aeb9',
    '96c843b3d34dde723261dc7ce11175ae',
    '07fb639dea2e898cb008bd98fb1c15bc',
    '7e6b57e5e15e32d6f3ca7ab7f181e370',
    '320bcaf73c2dca235f8a4c186f255e20',
    '4a3346c3e7cebee4e9a9054d587dacb2',
    'ac4c840689c50433504377aa63664188',
    'aef4792013bc3a56f8ee62bc1a7d686a',
    'f5c428ec7b6a3ecc2480a9330c69e27a',
    'bc347da48359f2e2427b36667ae15046'];
  c_after constant text[] := array[
    '1d9948cd8a49c58d54a83cb56c34656e',
    '350e02961ff61d5acdde7684e81c20b6',
    '96c185afbada30429ec9dce140a20fe7',
    '1e896989080f3da3f5ef7d72d51b5eb0',
    '7234e8bb7f2ed2cfefa8354bb9843d2d',
    'bec4ba292611157069c6813d22d04b9b',
    'd5db927d78c68df7148ee9c499f117ea',
    'e12563642234afde67989672f35b1c30',
    '152d825c64c76e83d2e91eaddd5df05e',
    '40e93118b55f19b5aa5cf1cf33baf678',
    '236cc0c0256e211a62788064d547e0a3',
    'e7067514af76bc9d20cb25b6544ee9d8',
    'a7fd9efd60794d3c2f5595b328ce7a75',
    '90a623e74ca682594d2be55d5b67935c',
    '086b5958fa3d0e7c40cd5f333602cb53',
    'cda58f1502d007f759ce9dda71c97ddf',
    '3fbeeb26dd744e36f1e2ce075defe8d2',
    '45bbe95629b8140649a5360296e68b7a'];
  c_acl constant text := 'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres';
  -- Every function here: search_path public, pg_temp.
  c_sp_old constant text := E' SET search_path TO ''public''\n';
  c_sp_new constant text := E' SET search_path TO ''public'', ''pg_temp''\n';
  -- The patches, each found exactly once in its function (c_fn: its place in c_sig).
  c_fn constant int[] := array[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 13, 14, 14, 15, 16, 16, 16, 17, 18];
  c_anchor constant text[] := array[
-- 1 affiliate_portal_login
$a$  if not exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'owner'
                    and p.is_active = true and p.deleted_at is null) then
    raise exception 'Only an Owner can see or unlink an affiliate login' using errcode = '42501'; end if;$a$,
-- 2 affiliate_staff_directory
$a$  perform public.require_active_staff();
  -- An active staff login of any role. Not a public endpoint.
  if auth.uid() is null or not exists (
       select 1 from public.profiles p where p.id = auth.uid() and p.is_active and p.deleted_at is null) then
    raise exception 'Sign in to view the affiliate directory' using errcode = '42501';
  end if;$a$,
-- 3 customer_match_candidates
$a$  if not exists (select 1 from public.profiles
                  where id = auth.uid() and is_active and deleted_at is null) then
    raise exception 'You do not have permission to look up customers' using errcode='42501'; end if;$a$,
-- 4 my_assigned_stores
$a$  with me as (
    select p.id, p.role from public.profiles p
     where p.id = auth.uid() and p.is_active = true
  ),$a$,
-- 5 record_invoice_handover
$a$  if not exists (select 1 from public.profiles
                  where id = auth.uid() and coalesce(is_active, true) and deleted_at is null) then
    raise exception 'Only an active user can hand over goods' using errcode = '42501'; end if;$a$,
-- 6 record_invoice_settlement
$a$ if not exists(select 1 from public.profiles
                where id=auth.uid() and coalesce(is_active,true) and deleted_at is null) then
  raise exception 'Only an active user can record a settlement' using errcode='42501'; end if;$a$,
-- 7 set_product_important
$a$  select role into v_role from public.profiles
   where id = auth.uid() and coalesce(is_active, true);$a$,
-- 8 staff_may_correct_invoice
$a$       and p.role = 'staff' and p.is_active and p.deleted_at is null$a$,
-- 9 stock_history_options
$a$ if not exists(select 1 from public.profiles where id=auth.uid() and is_active and deleted_at is null and role in ('owner','admin','manager','inventory_manager','staff')) then raise exception 'Stock History is available to internal staff only'; end if;$a$,
-- 10 tiktok_bank_payouts
$a$  if not exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_active and p.deleted_at is null
                   and p.role in ('owner', 'manager')) then
    raise exception 'Only an Owner or Manager can see the TikTok payouts'; end if;$a$,
-- 11 tiktok_xero_payouts
$a$  if not exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_active and p.deleted_at is null
                   and p.role in ('owner', 'manager')) then
    raise exception 'Only an Owner or Manager can export TikTok payouts for Xero'; end if;$a$,
-- 12 unlink_affiliate_account
$a$  if not exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'owner'
                    and p.is_active = true and p.deleted_at is null) then
    raise exception 'Only an Owner can unlink an affiliate login' using errcode = '42501'; end if;$a$,
-- 13 record_document_send: its variables
$a$declare v_id uuid;
$a$,
-- 14 record_document_send: the document looked up
$a$  perform public.require_active_staff();  -- 406: active staff only
  insert into public.document_sends (doc_kind, doc_id, doc_no, customer_id, channel,
    sent_to, pdf_path, status, error_text, sent_by)
  values (p_doc_kind, p_doc_id, p_doc_no, p_customer_id, p_channel,$a$,
-- 15 return_stock_loan: its header comment
$a$-- (good by default) and where it came back to, any active store, or a
-- warehouse with the warehouse stock permission; "used" (used / given away)$a$,
-- 16 return_stock_loan: its own place
$a$    if e->>'outcome' = 'returned' then
      if e->>'location_type' = 'warehouse' then$a$,
-- 17 stage_tiktok_orders
$a$    raise exception 'No rows to import'; end if;
$a$,
-- 18 set_product_prices: its variables
$a$declare v_price numeric := coalesce(p_member, p_non_member);
$a$,
-- 19 set_product_prices: the price before
$a$  insert into public.store_product_prices (store_id, product_id, selling_price, eligibility)
$a$,
-- 20 set_product_prices: the old price in the log
$a$    null, jsonb_build_object('store', p_store_id, 'price', v_price), 'pricing', null, p_store_id);$a$,
-- 21 stage_tiktok_settlement: the settled lines
$a$    raise exception 'No rows to import'; end if;
$a$,
-- 22 stage_tiktok_settlement_file: the Withdrawal records
$a$  -- Who may import, and the settled lines, exactly as before.
  v_batch := public.stage_tiktok_settlement(p_store_id, p_file_name, p_sheet_name, p_rows);
$a$];
  c_new constant text[] := array[
-- 1
$n$  -- 541 (security audit of 17 Nov 2026, L14): 406's test of an active member of staff (active, not
  -- deleted, invitation accepted; without a login, the same test of the claimed user), then an
  -- Owner only, as before.
  if coalesce(public.require_active_staff(), public.current_user_role()) is distinct from 'owner' then
    raise exception 'Only an Owner can see or unlink an affiliate login' using errcode = '42501'; end if;$n$,
-- 2
$n$  -- An active staff login of any role. Not a public endpoint. 541 (security audit of 17 Nov 2026,
  -- L14): that test alone (without a login, the same test of the claimed user); the secret key and
  -- the server's own work, which it lets by, are refused, as before.
  if coalesce(public.require_active_staff(), public.current_user_role()) is null then
    raise exception 'Sign in to view the affiliate directory' using errcode = '42501';
  end if;$n$,
-- 3
$n$  -- 541 (security audit of 17 Nov 2026, L14): 406's test of an active member of staff (without a
  -- login, the same test of the claimed user); the secret key and the server's own work, which it
  -- lets by, are refused, as before.
  if coalesce(public.require_active_staff(), public.current_user_role()) is null then
    raise exception 'You do not have permission to look up customers' using errcode='42501'; end if;$n$,
-- 4
$n$  with me as (
    -- 541 (security audit of 17 Nov 2026, L14): active staff as require_active_staff() tests it
    -- (active, not deleted, invitation accepted), without its refusal: anyone else gets no store.
    select p.id, p.role from public.profiles p
     where p.id = auth.uid() and p.role = public.current_user_role()
  ),$n$,
-- 5
$n$  -- 541 (security audit of 17 Nov 2026, L14): 406's test of an active member of staff (without a
  -- login, the same test of the claimed user); the secret key and the server's own work, which it
  -- lets by, are refused, as before.
  if coalesce(public.require_active_staff(), public.current_user_role()) is null then
    raise exception 'Only an active user can hand over goods' using errcode = '42501'; end if;$n$,
-- 6
$n$ -- 541 (security audit of 17 Nov 2026, L14): 406's test of an active member of staff (without a
 -- login, the same test of the claimed user); the secret key and the server's own work, which it
 -- lets by, are refused, as before.
 if coalesce(public.require_active_staff(), public.current_user_role()) is null then
  raise exception 'Only an active user can record a settlement' using errcode='42501'; end if;$n$,
-- 7
$n$  -- 541 (security audit of 17 Nov 2026, L14): 406's test of an active member of staff (not deleted,
  -- invitation accepted too; without a login, the same test of the claimed user); the secret key
  -- and the server's own work get no role from it and are refused below, as before.
  v_role := coalesce(public.require_active_staff(), public.current_user_role())::text;$n$,
-- 8
$n$       -- 541 (security audit of 17 Nov 2026, L14): active staff as require_active_staff() tests it
       -- (active, not deleted, invitation accepted), without its refusal: this answers.
       and p.role = 'staff' and p.role = public.current_user_role()$n$,
-- 9
$n$ -- 541 (security audit of 17 Nov 2026, L14): 406's test of an active member of staff (without a login, of the claimed user), then the five staff roles, as before.
 if coalesce(public.require_active_staff()::text, public.current_user_role()::text, '') not in ('owner','admin','manager','inventory_manager','staff') then raise exception 'Stock History is available to internal staff only'; end if;$n$,
-- 10
$n$  -- 541 (security audit of 17 Nov 2026, L14): 406's test of an active member of staff (without a
  -- login, the same test of the claimed user), then an Owner or a Manager, as before.
  if coalesce(public.require_active_staff()::text, public.current_user_role()::text, '') not in ('owner', 'manager') then
    raise exception 'Only an Owner or Manager can see the TikTok payouts'; end if;$n$,
-- 11
$n$  -- 541 (security audit of 17 Nov 2026, L14): 406's test of an active member of staff (without a
  -- login, the same test of the claimed user), then an Owner or a Manager, as before.
  if coalesce(public.require_active_staff()::text, public.current_user_role()::text, '') not in ('owner', 'manager') then
    raise exception 'Only an Owner or Manager can export TikTok payouts for Xero'; end if;$n$,
-- 12
$n$  -- 541 (security audit of 17 Nov 2026, L14): 406's test of an active member of staff (active, not
  -- deleted, invitation accepted; without a login, the same test of the claimed user), then an
  -- Owner only, as before.
  if coalesce(public.require_active_staff(), public.current_user_role()) is distinct from 'owner' then
    raise exception 'Only an Owner can unlink an affiliate login' using errcode = '42501'; end if;$n$,
-- 13
$n$declare v_id uuid; v_no text; v_customer uuid; v_ok boolean;
$n$,
-- 14
$n$  perform public.require_active_staff();  -- 406: active staff only
  -- 541 (security audit of 17 Nov 2026, L16): a send is logged against a document the caller can
  -- see: an invoice, not deleted, of a store they have access to (as record_document_printed); a
  -- special sale or a rental as their read rules (a Manager and up, or access to its store or to
  -- the store it came from). Its number and customer are the document's own; p_doc_no and
  -- p_customer_id are no longer read.
  if p_doc_kind = 'invoice' then
    select i.invoice_no, i.customer_id, public.user_has_store_access(i.store_id)
      into v_no, v_customer, v_ok
      from public.invoices i where i.id = p_doc_id and i.deleted_at is null;
  elsif p_doc_kind = 'special_sale' then
    select s.sale_no, s.customer_id,
           public.is_manager_or_above() or public.user_has_store_access(s.store_id)
             or public.user_has_store_access(s.source_store_id)
      into v_no, v_customer, v_ok
      from public.special_sales s where s.id = p_doc_id;
  elsif p_doc_kind = 'rental' then
    select r.rental_no, r.customer_id,
           public.is_manager_or_above() or public.user_has_store_access(r.store_id)
             or public.user_has_store_access(r.source_store_id)
      into v_no, v_customer, v_ok
      from public.rentals r where r.id = p_doc_id;
  else
    raise exception 'Unknown document kind "%"', p_doc_kind using errcode = '22023';
  end if;
  if not coalesce(v_ok, false) or v_no is null then
    raise exception 'That document is not one you can see.' using errcode = '42501';
  end if;
  insert into public.document_sends (doc_kind, doc_id, doc_no, customer_id, channel,
    sent_to, pdf_path, status, error_text, sent_by)
  values (p_doc_kind, p_doc_id, v_no, v_customer, p_channel,$n$,
-- 15
$n$-- (good by default) and where it came back to: 541 (the user, 26 Nov 2026), the
-- loan's own store or warehouse; an Owner or a Manager may name any active
-- store, or a warehouse with the warehouse stock permission (401 took any
-- active store); "used" (used / given away)$n$,
-- 16
$n$    if e->>'outcome' = 'returned' then
      -- 541 (security audit of 17 Nov 2026, L19; the user, 26 Nov 2026): back into the loan's own
      -- store or warehouse. Only an Owner or a Manager may name another active store, or a
      -- warehouse they hold the warehouse stock permission for (the checks below). The event row
      -- records where it went.
      if (e->>'location_type', (e->>'location_id')::uuid)
           is distinct from (l.location_type, coalesce(l.store_id, l.warehouse_id))
         and coalesce(public.current_user_role()::text, '') not in ('owner', 'manager') then
        raise exception '% was lent from %, so it comes back there. Only an Owner or a Manager can take it back into another store or warehouse.',
          l.loan_no, coalesce((select s.name from public.stores s where s.id = l.store_id),
                              (select w.name from public.warehouses w where w.id = l.warehouse_id))
          using errcode = '42501'; end if;
      if e->>'location_type' = 'warehouse' then$n$,
-- 17
$n$    raise exception 'No rows to import'; end if;
  -- 541 (security audit of 17 Nov 2026, L19): at most 20,000 rows, the page's own limit for a file
  -- (MAX_IMPORT_ROWS, src/lib/tiktok/readSpreadsheet.mjs); the page sends a file's rows in one call.
  if jsonb_array_length(p_rows) > 20000 then
    raise exception 'A TikTok file has at most 20,000 rows. Please export a shorter date range and try again.'
      using errcode = '54000'; end if;
$n$,
-- 18
$n$declare v_price numeric := coalesce(p_member, p_non_member); v_old public.store_product_prices%rowtype;
$n$,
-- 19
$n$  -- 541 (security audit of 17 Nov 2026, L19): the price this replaces, for the change log (locked,
  -- so it is the one replaced).
  select * into v_old from public.store_product_prices
   where store_id = p_store_id and product_id = p_product_id for update;
  insert into public.store_product_prices (store_id, product_id, selling_price, eligibility)
$n$,
-- 20
$n$    -- 541: the old price beside the new one (none when the store had no price for it; removed when
    -- its price had been taken off the list).
    case when v_old.id is not null then jsonb_build_object('store', p_store_id, 'price', v_old.selling_price)
      || case when v_old.deleted_at is not null then jsonb_build_object('removed', true) else '{}'::jsonb end end,
    jsonb_build_object('store', p_store_id, 'price', v_price), 'pricing', null, p_store_id);$n$,
-- 21
$n$    raise exception 'No rows to import'; end if;
  -- 541 (security audit of 17 Nov 2026, L19): at most 20,000 rows, the page's own limit for a sheet
  -- (MAX_IMPORT_ROWS, src/lib/tiktok/readSpreadsheet.mjs); the page sends a file's settled lines in
  -- one call (through stage_tiktok_settlement_file).
  if jsonb_array_length(p_rows) > 20000 then
    raise exception 'A TikTok file has at most 20,000 rows. Please export a shorter date range and try again.'
      using errcode = '54000'; end if;
$n$,
-- 22
$n$  -- 541 (security audit of 17 Nov 2026, L19): who may import first, then at most 20,000 Withdrawal
  -- records, the page's own limit for a sheet (they come from one sheet of the file,
  -- src/lib/tiktok/withdrawals.mjs), before anything is staged.
  perform public.tiktok_access_check(p_store_id);
  if jsonb_typeof(p_balance_rows) = 'array' and jsonb_array_length(p_balance_rows) > 20000 then
    raise exception 'A TikTok file''s Withdrawal records have at most 20,000 rows. Please export a shorter date range and try again.'
      using errcode = '54000'; end if;
  -- Who may import, and the settled lines, exactly as before.
  v_batch := public.stage_tiktok_settlement(p_store_id, p_file_name, p_sheet_name, p_rows);
$n$];
  -- The buckets: before and after (public, size limit, types); invoice-pdfs relied on as it is.
  c_bk constant text[] := array['store-assets', 'survey-attachments'];
  c_bk_public constant boolean[] := array[true, false];
  c_bk_limit_before constant bigint[] := array[null, 10485760];
  c_bk_limit_after constant bigint[] := array[5242880, 10485760];
  c_bk_types_before constant text[] := array[
    null,
    'image/*,application/pdf,application/msword,application/vnd.openxmlformats-officedocument.wordprocessingml.document,application/vnd.ms-excel,application/vnd.openxmlformats-officedocument.spreadsheetml.sheet,text/csv,text/plain'];
  c_bk_types_after constant text[] := array[
    'image/png,image/jpeg,image/webp',
    'image/jpeg,image/png,image/gif,image/webp,image/heic,image/heif,application/pdf,application/msword,application/vnd.openxmlformats-officedocument.wordprocessingml.document,application/vnd.ms-excel,application/vnd.openxmlformats-officedocument.spreadsheetml.sheet,text/csv,text/plain'];

  v_path text := current_setting('search_path');
  v_lock text := current_setting('lock_timeout');
  v_def text[] := array_fill(null::text, array[cardinality(c_sig)]);
  v_done int := 0; v_bk_done int := 0; v_bad text := ''; d text; i int; v_n int;
begin
  -- Definitions are read and compared with public alone on the search path.
  perform set_config('search_path', 'public', true);
  -- A busy function or table waits 5 seconds at most, then this refuses whole.
  perform set_config('lock_timeout', '5s', true);

  -- 1. Checks: nothing is changed before all of them pass
  for i in 1 .. cardinality(c_relied) loop
    if to_regprocedure('public.' || c_relied[i]) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i]))) <> c_relied_md5[i] then
      raise exception '541: public.% is missing or not the version this was tested against (540 must be in). Re-read it and re-test before applying.', c_relied[i];
    end if;
  end loop;
  for i in 1 .. cardinality(c_sig) loop
    if to_regprocedure('public.' || c_sig[i]) is null then raise exception '541: public.% is missing', c_sig[i]; end if;
    d := pg_get_functiondef(to_regprocedure('public.' || c_sig[i]));
    if (select coalesce(string_agg(x::text, ',' order by x::text), '')
          from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig[i])) is distinct from c_acl then
      raise exception '541: the grants of public.% are not the tested ones. Re-read them before applying.', c_sig[i]; end if;
    if md5(d) = c_after[i] then
      v_done := v_done + 1;
    elsif md5(d) = c_before[i] then
      v_def[i] := d;
    else
      raise exception '541: public.% is not the version this was tested against (md5 %). Re-read it and re-test before applying.', c_sig[i], md5(d);
    end if;
  end loop;
  if (select count(*) from storage.buckets b where b.id = 'invoice-pdfs' and not b.public
       and b.file_size_limit = 10485760 and b.allowed_mime_types = array['application/pdf']) <> 1 then
    raise exception '541: the bucket invoice-pdfs is not the one this was tested against. Re-read it before applying.'; end if;
  for i in 1 .. cardinality(c_bk) loop
    select count(*) into v_n from storage.buckets b where b.id = c_bk[i] and b.public = c_bk_public[i];
    if v_n <> 1 then raise exception '541: the bucket % is missing or not the one this was tested against.', c_bk[i]; end if;
    if exists (select 1 from storage.buckets b where b.id = c_bk[i]
                and b.file_size_limit is not distinct from c_bk_limit_after[i]
                and array_to_string(b.allowed_mime_types, ',') is not distinct from c_bk_types_after[i]) then
      v_bk_done := v_bk_done + 1;
    elsif not exists (select 1 from storage.buckets b where b.id = c_bk[i]
                and b.file_size_limit is not distinct from c_bk_limit_before[i]
                and array_to_string(b.allowed_mime_types, ',') is not distinct from c_bk_types_before[i]) then
      raise exception '541: the rules of the bucket % are not the ones this was tested against. Re-read them before applying.', c_bk[i];
    end if;
    -- No file already there falls outside the new rule (it would not be touched, but the rule
    -- would then be false for it).
    select count(*) into v_n from storage.objects o where o.bucket_id = c_bk[i]
       and (coalesce(o.metadata ->> 'mimetype', '') <> all (string_to_array(c_bk_types_after[i], ','))
            or coalesce((o.metadata ->> 'size')::bigint, 0) > c_bk_limit_after[i]);
    if v_n > 0 then
      raise exception '541: % file(s) in the bucket % are outside its new rule. Re-read them before applying.', v_n, c_bk[i]; end if;
  end loop;
  if v_done = cardinality(c_sig) and v_bk_done = cardinality(c_bk) then
    raise exception '541 is already in on this database; nothing was changed.'; end if;
  if v_done > 0 or v_bk_done > 0 then
    raise exception '541: only part of it is in on this database (% of % functions patched, % of % buckets). Re-read them before applying; nothing was changed.',
      v_done, cardinality(c_sig), v_bk_done, cardinality(c_bk); end if;
  -- The patches, then the search path; each result exactly the tested text.
  for i in 1 .. cardinality(c_fn) loop
    if (length(v_def[c_fn[i]]) - length(replace(v_def[c_fn[i]], c_anchor[i], ''))) / length(c_anchor[i]) <> 1 then
      raise exception '541: patch % does not find its text exactly once in public.%', i, c_sig[c_fn[i]]; end if;
    v_def[c_fn[i]] := replace(v_def[c_fn[i]], c_anchor[i], c_new[i]);
  end loop;
  for i in 1 .. cardinality(c_sig) loop
    if (length(v_def[i]) - length(replace(v_def[i], c_sp_old, ''))) / length(c_sp_old) <> 1 then
      raise exception '541: public.% has no single search_path public', c_sig[i]; end if;
    v_def[i] := replace(v_def[i], c_sp_old, c_sp_new);
    if md5(v_def[i]) <> c_after[i] then v_bad := v_bad || format(E'\n%s=%s', c_sig[i], md5(v_def[i])); end if;
  end loop;
  if v_bad <> '' then
    raise exception '541: the patched text is not the tested one:%', v_bad; end if;

  -- 2. Install
  for i in 1 .. cardinality(c_sig) loop
    execute v_def[i];
  end loop;
  for i in 1 .. cardinality(c_bk) loop
    update storage.buckets set file_size_limit = c_bk_limit_after[i],
                               allowed_mime_types = string_to_array(c_bk_types_after[i], ','),
                               updated_at = now()
     where id = c_bk[i];
  end loop;

  -- 3. Checks after installing
  for i in 1 .. cardinality(c_sig) loop
    if md5(pg_get_functiondef(to_regprocedure('public.' || c_sig[i]))) <> c_after[i] then
      raise exception '541: public.% was installed with an md5 other than the tested one', c_sig[i]; end if;
    if (select coalesce(string_agg(x::text, ',' order by x::text), '')
          from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig[i])) is distinct from c_acl
       or (select p.proconfig from pg_proc p where p.oid = to_regprocedure('public.' || c_sig[i])) is distinct from array['search_path=public, pg_temp'] then
      raise exception '541: the grants or the search path of public.% are not the tested ones', c_sig[i]; end if;
  end loop;
  for i in 1 .. cardinality(c_bk) loop
    if not exists (select 1 from storage.buckets b where b.id = c_bk[i] and b.public = c_bk_public[i]
                    and b.file_size_limit is not distinct from c_bk_limit_after[i]
                    and array_to_string(b.allowed_mime_types, ',') is not distinct from c_bk_types_after[i]) then
      raise exception '541: the bucket % is not as tested after installing', c_bk[i]; end if;
  end loop;
  if (select count(*) from storage.buckets b where b.id = 'invoice-pdfs' and not b.public
       and b.file_size_limit = 10485760 and b.allowed_mime_types = array['application/pdf']) <> 1 then
    raise exception '541: the bucket invoice-pdfs changed'; end if;
  for i in 1 .. cardinality(c_relied) loop
    if md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i]))) <> c_relied_md5[i] then
      raise exception '541: public.% changed', c_relied[i]; end if;
  end loop;

  perform set_config('lock_timeout', v_lock, true);
  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $mig$;
