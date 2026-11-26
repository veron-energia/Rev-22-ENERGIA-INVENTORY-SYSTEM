-- UNDO of 541 (with the user's go-ahead). It takes 541's text out of the 18 functions it changed
-- (the L14 active-staff test in twelve, the L16 document look-up in record_document_send, the L19
-- loan place rule in return_stock_loan, the row limits in stage_tiktok_orders, stage_tiktok_settlement
-- and stage_tiktok_settlement_file, the old price in set_product_prices, and the search path
-- public, pg_temp in all 18), putting each back exactly as
-- before 541 (md5s below), and puts the rules of the buckets store-assets (no limits) and
-- survey-attachments (image/* first) back as they were. Afterwards a Staff member can take a loan
-- back into any active store again, the send log takes the browser's document number and customer
-- again, and a TikTok file has no server row limit: L13, L14, L16 and L19 open again. Audit Log
-- entries written since 541 keep their old prices; files uploaded since 541 stay. Run it BEFORE
-- scripts/customers/undo-540.sql.
--
-- It refuses, with nothing changed, unless every function and bucket 541 changed is exactly
-- 541's. One transaction, all or nothing; it waits at most 5 seconds for a lock. The 541 row in
-- supabase_migrations.schema_migrations stays; with the user's OK, remove that one row or record
-- this UNDO beside it.
do $undo$
declare
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
  d text; i int;
begin
  perform set_config('search_path', 'public', true);
  perform set_config('lock_timeout', '5s', true);

  -- 1. Checks: nothing is changed before all of them pass
  for i in 1 .. cardinality(c_sig) loop
    if to_regprocedure('public.' || c_sig[i]) is null then
      raise exception 'undo 541: public.% is missing. Nothing was changed.', c_sig[i]; end if;
    d := pg_get_functiondef(to_regprocedure('public.' || c_sig[i]));
    if md5(d) = c_before[i] then
      raise exception 'undo 541: public.% is already its version of before 541; 541 is not in. Nothing was changed.', c_sig[i]; end if;
    if md5(d) <> c_after[i] then
      raise exception 'undo 541: public.% is not 541''s version (md5 %). Nothing was changed.', c_sig[i], md5(d); end if;
    if (select coalesce(string_agg(x::text, ',' order by x::text), '')
          from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig[i])) is distinct from c_acl then
      raise exception 'undo 541: the grants of public.% are not the tested ones. Nothing was changed.', c_sig[i]; end if;
    if (length(d) - length(replace(d, c_sp_new, ''))) / length(c_sp_new) <> 1 then
      raise exception 'undo 541: public.% has no single search_path public, pg_temp. Nothing was changed.', c_sig[i]; end if;
    v_def[i] := replace(d, c_sp_new, c_sp_old);
  end loop;
  for i in reverse cardinality(c_fn) .. 1 loop
    if (length(v_def[c_fn[i]]) - length(replace(v_def[c_fn[i]], c_new[i], ''))) / length(c_new[i]) <> 1 then
      raise exception 'undo 541: 541''s text % is not found exactly once in public.%. Nothing was changed.', i, c_sig[c_fn[i]]; end if;
    v_def[c_fn[i]] := replace(v_def[c_fn[i]], c_new[i], c_anchor[i]);
  end loop;
  for i in 1 .. cardinality(c_sig) loop
    if md5(v_def[i]) <> c_before[i] then
      raise exception 'undo 541: public.% without 541''s text is not its version of before 541 (md5 %). Nothing was changed.', c_sig[i], md5(v_def[i]); end if;
  end loop;
  for i in 1 .. cardinality(c_bk) loop
    if not exists (select 1 from storage.buckets b where b.id = c_bk[i] and b.public = c_bk_public[i]
                    and b.file_size_limit is not distinct from c_bk_limit_after[i]
                    and array_to_string(b.allowed_mime_types, ',') is not distinct from c_bk_types_after[i]) then
      raise exception 'undo 541: the rules of the bucket % are not 541''s. Nothing was changed.', c_bk[i]; end if;
  end loop;

  -- 2. Put back
  for i in 1 .. cardinality(c_sig) loop
    execute v_def[i];
  end loop;
  for i in 1 .. cardinality(c_bk) loop
    update storage.buckets set file_size_limit = c_bk_limit_before[i],
                               allowed_mime_types = string_to_array(c_bk_types_before[i], ','),
                               updated_at = now()
     where id = c_bk[i];
  end loop;

  -- 3. Checks after
  for i in 1 .. cardinality(c_sig) loop
    if md5(pg_get_functiondef(to_regprocedure('public.' || c_sig[i]))) <> c_before[i]
       or (select coalesce(string_agg(x::text, ',' order by x::text), '')
             from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig[i])) is distinct from c_acl then
      raise exception 'undo 541: public.% is not as before 541 after putting it back', c_sig[i]; end if;
  end loop;
  for i in 1 .. cardinality(c_bk) loop
    if not exists (select 1 from storage.buckets b where b.id = c_bk[i] and b.public = c_bk_public[i]
                    and b.file_size_limit is not distinct from c_bk_limit_before[i]
                    and array_to_string(b.allowed_mime_types, ',') is not distinct from c_bk_types_before[i]) then
      raise exception 'undo 541: the bucket % is not as before 541 after putting it back', c_bk[i]; end if;
  end loop;

  perform set_config('lock_timeout', v_lock, true);
  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $undo$;
