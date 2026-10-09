-- 407_staff_tables_files_and_profiles.sql
--
-- WHAT WAS WRONG (audit of 8 Oct 2026; access inventory of 9 Oct 2026)
--
--   The rest of the same mistake as 406: rules written when only staff could
--   sign in. 406 makes the server functions check the caller; this does the
--   tables, the invoice PDF folder and the staff profiles.
--
--   1. Readable by any signed-in login (X-4). The read rules of 47 tables say
--      "true" (or "anyone signed in", or "not deleted"). An affiliate login,
--      or one made by anyone at /affiliate/join, read every product with its
--      cost price and supplier, every store price, both stores' bank account,
--      PayNow UEN and company number, the commission rates, every promotion,
--      package and voucher, and the customer and invoice ids and amounts in
--      the credit-package and premium-bundle splits and voucher redemptions.
--      No page an affiliate or a signed-out visitor opens reads any of them.
--   2. The invoice PDF folder (X-2). Sending an invoice by WhatsApp or email
--      uploads the customer copy to the private invoice-pdfs folder, and the
--      customer gets a link valid for a year. Its read, upload and replace
--      rules checked only the folder name, so any signed-in login could list
--      and download all 29 customer PDFs, and could REPLACE one: the link a
--      customer already holds would then show a forged invoice, "How to pay"
--      bank details included. The folder had no size or type limit.
--   3. Approval requests (X-6). Every real request is written by a server
--      function, but the table also took direct inserts from any staff login
--      ("insert approval requests") and direct edits from managers ("update
--      approval requests"). A staff member could post a stock adjustment
--      showing "10 -> 12" while the warehouse held 500; approving it set the
--      warehouse to 12. A stray pending request also blocks refunds and staff
--      corrections of its invoice. The page only reads the table.
--   4. Managers' edits on Users & Roles saved nothing (ADMIN-AUTH-2). The
--      update rule on profiles let a login change its own row, or an Owner or
--      Admin any row. The page offers a Manager Edit on Staff and Inventory
--      Managers (what can_assign_role allows), the save "succeeded" with no
--      row changed, and the old values came back: a Manager who deactivated a
--      leaver had not. Both Managers on production are affected.
--   5. Any member of staff could change their own login email, deleted date
--      or invitation state (ADMIN-AUTH-M3). The users list hides a profile
--      with a deleted date, so a staff member could vanish from Users & Roles
--      and keep their access. The profile guard trigger watched only the role
--      and "active". An Owner could also tick Active on a pending or cancelled
--      invitee (ADMIN-AUTH-13), which the rules that test only "active" would
--      take for staff while current_user_role() (406) does not.
--   6. A deactivated employee still read their own approval requests, staff
--      commissions and commission payouts: those rules let "my own row"
--      through without asking whether the person still works here (X-5,
--      review of 9 Oct). And a store's staff could still replace that store's
--      PDFs, the 29 already sent included, behind links customers hold.
--
-- THE RULES (the Owner approved the fix on 9 Oct 2026, "Security (urgent)")
--
--   1. The 47 tables are read by active staff only (current_user_role(),
--      active since 406). Every staff role still reads every one of them, as
--      today; promotions and vouchers still hide deleted rows.
--   2. A PDF in invoice-pdfs is read or uploaded only by active staff who
--      work at the store it is filed under (its first folder), or by a
--      Manager, Admin or Owner: the rule survey-attachments already uses.
--      Replacing a PDF is an Owner's or Manager's, as deleting one already is.
--      Only PDFs, of at most 10 MB (the 29 there are 8 to 11 kB). The pages
--      now file each send under a new name and never replace a file, so a
--      link always shows the copy that was sent (front end).
--   3. Approval requests are written by the server functions alone. Staff
--      still read their own requests and Managers all, as before.
--   4. A Manager may edit the Inventory Managers and Staff the page offers
--      them, and set only those two roles, as can_assign_role and the profile
--      guard trigger say. An active login may still edit its own name and
--      contact details. Owners and Admins as before.
--   5. A profile's id, login email, creation time, deleted date and
--      invitation state are written by the server alone: the invitation
--      functions (which declare their intent) and the service role. No page
--      writes them; the login email is changed in Supabase Auth. An invitee
--      becomes active by accepting the invitation, not by an edit.
--   6. The send log and the audit log are written by server functions alone
--      (no rule ever let a login write them; this takes the grants away too).
--   7. A person reads their own approval requests, commissions and payouts
--      while they are active staff (current_user_role()); Managers and up
--      read them all, as before.
--
-- WHAT THIS DOES
--
--   * The read rules of the 47 tables: "true" (or "auth.uid() is not null")
--     becomes "(select current_user_role()) is not null", and the two "not
--     deleted" rules keep that test beside it. The five that applied to every
--     role, signed-out visitors included (the split tables and the spending
--     rules), now apply to signed-in logins, as the rest; signed out, no rule
--     applies and nothing is read, as before.
--   * invoice-pdfs: the read and upload rules become rule 2's, the replace
--     rule the delete rule's (is_owner_or_manager()); the bucket takes
--     application/pdf only, at most 10 MB.
--   * "read approval requests", "read staff commissions" and "read staff
--     payouts": the own-row half also asks for an active member of staff.
--   * approval_requests: the two write rules are dropped, and signed-in
--     logins keep SELECT alone (anon nothing). The same grants are taken from
--     audit_logs and document_sends.
--   * "update profiles": an active login's own row, an Owner's or Admin's any
--     row (as before), or a Manager's Inventory Manager and Staff rows, before
--     and after the edit.
--   * trg_guard_profile_privileges() (patched): refuses a change to id,
--     email, created_at, deleted_at or invitation_status, and switching on a
--     profile whose invitation is not accepted, unless the server makes it
--     (energia.profile_privilege_change, or no signed-in user).
--
-- NOT CHANGED
--
--   * health_symptom_options and customer_source_options (the public survey
--     reads them signed out), the tables already read by staff or by their own
--     store or role (transfers, stock, invoices, customers and the rest), and
--     every write rule but the two dropped and the PDF replace rule.
--   * survey-attachments, store-assets, the PDF delete rule, the 29 PDFs and
--     the links already sent.
--   * The affiliate portal reads none of these tables: its functions run as
--     the owner.
--   * No row, except the bucket's two limits.
--
-- SAFETY
--
--   Apart from the lock timeout this is one DO block, so it is atomic. It
--   refuses unless 406 is in (current_user_role() at 406's version) and every
--   rule it changes or drops reads exactly as on production on 9 Oct 2026 (or
--   already as this migration leaves it, so a re-run changes nothing); the
--   trigger function is the version read that day (or this one), its anchor
--   occurs once and the text built has its AFTER md5; the trigger is on
--   profiles, before update. Afterwards every rule reads as tested, the
--   grants are as above, and, switching role: a signed-in login with no
--   profile reads no row of the 47 tables and no PDF, and cannot insert an
--   approval request; an active Owner, when there is one, still reads
--   products and stores. Nothing is printed.
--
-- BEFORE (production, 9 Oct 2026; md5 of pg_get_functiondef):
--   trg_guard_profile_privileges()          07f4782e6eebcfe31495a2a682cfc418
--   (relied on, not changed)
--   profile_privilege_change_allowed()      5fa0c10e9eb0c7007e87a2baf5d36264
--   is_owner_or_admin()                     3856bdf5ed650fe84e2304ec4f0f0a68
--   is_manager_or_above()                   f12b9ed342070fa4defa30e4da2ba655
--   is_owner_or_manager()                   125dec10ce33b84ff5fb40a9bd455235
--   user_has_store_access(uuid)             8c82c6bcb64f496c5a05a2b8dafa95f8
--   survey_attachment_store(text)           58f7d30040f104d240b40ec3e9d9567f
--   current_user_role()                     519b0a33a3548f970c5d585b6e76a389  (406's AFTER)
-- AFTER (for later guards):
--   trg_guard_profile_privileges()          903ce9d75b2d0314428fb298a185d781
--
-- DEPLOY ORDER: 406, then this straight after, then the front end, then reload
-- the app on the shop's devices. The pages live now keep working: every staff
-- role still reads the 47 tables; the Users page's save now changes the row
-- it always meant to; a first send of a document uploads as before. Only a
-- re-send from a page opened before the new front end changes: it replaces
-- the earlier file under the same name, which now only an Owner or Manager
-- may do, so Staff see "Could not upload the PDF" until they reload the app
-- (the new pages file each send under a new name and never replace one).
--
-- Test: scripts/permissions/tests/staff-only-functions.sql (as each role, and
-- as logins that are not staff), scripts/permissions/tests/rls-policies.sql.

set lock_timeout = '5s';

do $mig$
declare
  c_trg_before constant text := '07f4782e6eebcfe31495a2a682cfc418';
  c_trg_after  constant text := '903ce9d75b2d0314428fb298a185d781';
  c_trg_anchor constant text := $a$begin
  if not v_role_changed and not v_active_changed then
$a$;
  c_trg_repl   constant text := $r$begin
  -- 407: who a profile is (id, login email, when it was made), whether it is
  -- deleted and where its invitation stands are the server's to write: the
  -- invitation functions, which declare their intent, the service role and
  -- the database itself. A request from a browser (the anon or authenticated
  -- role) may not, or a login could hide itself from Users & Roles and keep
  -- its access.
  if (new.id is distinct from old.id or new.email is distinct from old.email
      or new.created_at is distinct from old.created_at
      or new.deleted_at is distinct from old.deleted_at
      or new.invitation_status is distinct from old.invitation_status)
     and coalesce(auth.role(), '') in ('anon', 'authenticated')
     and not public.profile_privilege_change_allowed() then
    raise exception 'A profile''s login email, deletion and invitation state are changed by the system only.'
      using errcode = '42501';
  end if;
  -- 407: an invitee becomes active by accepting the invitation, never by having
  -- Active ticked from a page; the rules that test only is_active would
  -- otherwise let them in while current_user_role() (406) says they are nobody.
  if v_active_changed and new.is_active and coalesce(new.invitation_status, 'accepted') <> 'accepted'
     and coalesce(auth.role(), '') in ('anon', 'authenticated')
     and not public.profile_privilege_change_allowed() then
    raise exception 'An invited person becomes active by accepting their invitation.'
      using errcode = '42501';
  end if;
  if not v_role_changed and not v_active_changed then
$r$;
  c_role_406   constant text := '519b0a33a3548f970c5d585b6e76a389';
  c_upd_before constant text := '((id = auth.uid()) OR is_owner_or_admin())';
  c_upd_after  constant text := '(((id = auth.uid()) AND (current_user_role() IS NOT NULL)) OR is_owner_or_admin() OR ((current_user_role() = ''manager''::user_role) AND (role = ANY (ARRAY[''inventory_manager''::user_role, ''staff''::user_role]))))';
  c_mb constant bigint := 10485760;          -- 10 MB
  -- The 47 read rules: table, rule, roles and qualifier as read on 9 Oct 2026,
  -- the qualifier as this leaves it (as pg_policies prints it), and the new one.
  c_rules constant text[][] := array[
    ['app_settings', 'read settings', '{authenticated}', 'true',
     '(( SELECT current_user_role() AS current_user_role) IS NOT NULL)', '(select public.current_user_role()) is not null'],
    ['brands', 'brands read', '{authenticated}', 'true',
     '(( SELECT current_user_role() AS current_user_role) IS NOT NULL)', '(select public.current_user_role()) is not null'],
    ['categories', 'categories read', '{authenticated}', 'true',
     '(( SELECT current_user_role() AS current_user_role) IS NOT NULL)', '(select public.current_user_role()) is not null'],
    ['credit_package_spending_rules', 'read credit package spending rules', '{public}', '(auth.uid() IS NOT NULL)',
     '(( SELECT current_user_role() AS current_user_role) IS NOT NULL)', '(select public.current_user_role()) is not null'],
    ['credit_package_split_allocations', 'read split allocations', '{public}', '(auth.uid() IS NOT NULL)',
     '(( SELECT current_user_role() AS current_user_role) IS NOT NULL)', '(select public.current_user_role()) is not null'],
    ['credit_package_split_groups', 'read split groups', '{public}', '(auth.uid() IS NOT NULL)',
     '(( SELECT current_user_role() AS current_user_role) IS NOT NULL)', '(select public.current_user_role()) is not null'],
    ['credit_package_stores', 'read credit packages', '{authenticated}', 'true',
     '(( SELECT current_user_role() AS current_user_role) IS NOT NULL)', '(select public.current_user_role()) is not null'],
    ['credit_package_vouchers', 'read credit packages', '{authenticated}', 'true',
     '(( SELECT current_user_role() AS current_user_role) IS NOT NULL)', '(select public.current_user_role()) is not null'],
    ['credit_packages', 'read credit packages', '{authenticated}', 'true',
     '(( SELECT current_user_role() AS current_user_role) IS NOT NULL)', '(select public.current_user_role()) is not null'],
    ['foc_reasons', 'read foc reasons', '{authenticated}', 'true',
     '(( SELECT current_user_role() AS current_user_role) IS NOT NULL)', '(select public.current_user_role()) is not null'],
    ['payment_methods', 'read payment methods', '{authenticated}', 'true',
     '(( SELECT current_user_role() AS current_user_role) IS NOT NULL)', '(select public.current_user_role()) is not null'],
    ['premium_bundle_split_allocations', 'read bundle split allocations', '{public}', '(auth.uid() IS NOT NULL)',
     '(( SELECT current_user_role() AS current_user_role) IS NOT NULL)', '(select public.current_user_role()) is not null'],
    ['premium_bundle_split_groups', 'read bundle split groups', '{public}', '(auth.uid() IS NOT NULL)',
     '(( SELECT current_user_role() AS current_user_role) IS NOT NULL)', '(select public.current_user_role()) is not null'],
    ['premium_bundle_stores', 'read premium bundles', '{authenticated}', 'true',
     '(( SELECT current_user_role() AS current_user_role) IS NOT NULL)', '(select public.current_user_role()) is not null'],
    ['premium_bundle_vouchers', 'read premium bundles', '{authenticated}', 'true',
     '(( SELECT current_user_role() AS current_user_role) IS NOT NULL)', '(select public.current_user_role()) is not null'],
    ['premium_bundles', 'read premium bundles', '{authenticated}', 'true',
     '(( SELECT current_user_role() AS current_user_role) IS NOT NULL)', '(select public.current_user_role()) is not null'],
    ['product_categories', 'product_categories read', '{authenticated}', 'true',
     '(( SELECT current_user_role() AS current_user_role) IS NOT NULL)', '(select public.current_user_role()) is not null'],
    ['product_suppliers', 'product_suppliers read', '{authenticated}', 'true',
     '(( SELECT current_user_role() AS current_user_role) IS NOT NULL)', '(select public.current_user_role()) is not null'],
    ['products', 'read products', '{authenticated}', 'true',
     '(( SELECT current_user_role() AS current_user_role) IS NOT NULL)', '(select public.current_user_role()) is not null'],
    ['promotion_choice_groups', 'read choice groups', '{authenticated}', 'true',
     '(( SELECT current_user_role() AS current_user_role) IS NOT NULL)', '(select public.current_user_role()) is not null'],
    ['promotion_choice_options', 'read choice options', '{authenticated}', 'true',
     '(( SELECT current_user_role() AS current_user_role) IS NOT NULL)', '(select public.current_user_role()) is not null'],
    ['promotion_items', 'read promotion items', '{authenticated}', 'true',
     '(( SELECT current_user_role() AS current_user_role) IS NOT NULL)', '(select public.current_user_role()) is not null'],
    ['promotion_store_prices', 'read promotion prices', '{authenticated}', 'true',
     '(( SELECT current_user_role() AS current_user_role) IS NOT NULL)', '(select public.current_user_role()) is not null'],
    ['promotions', 'read promotions', '{authenticated}', '(deleted_at IS NULL)',
     '((deleted_at IS NULL) AND (( SELECT current_user_role() AS current_user_role) IS NOT NULL))', '(deleted_at is null) and (select public.current_user_role()) is not null'],
    ['special_product_stock', 'read special stock', '{authenticated}', 'true',
     '(( SELECT current_user_role() AS current_user_role) IS NOT NULL)', '(select public.current_user_role()) is not null'],
    ['special_products', 'read special products', '{authenticated}', 'true',
     '(( SELECT current_user_role() AS current_user_role) IS NOT NULL)', '(select public.current_user_role()) is not null'],
    ['store_product_prices', 'read store prices', '{authenticated}', 'true',
     '(( SELECT current_user_role() AS current_user_role) IS NOT NULL)', '(select public.current_user_role()) is not null'],
    ['stores', 'read stores', '{authenticated}', 'true',
     '(( SELECT current_user_role() AS current_user_role) IS NOT NULL)', '(select public.current_user_role()) is not null'],
    ['suppliers', 'suppliers read', '{authenticated}', 'true',
     '(( SELECT current_user_role() AS current_user_role) IS NOT NULL)', '(select public.current_user_role()) is not null'],
    ['therapy_calendar_coverage', 'read_coverage', '{authenticated}', 'true',
     '(( SELECT current_user_role() AS current_user_role) IS NOT NULL)', '(select public.current_user_role()) is not null'],
    ['therapy_closure_dates', 'read_closures', '{authenticated}', 'true',
     '(( SELECT current_user_role() AS current_user_role) IS NOT NULL)', '(select public.current_user_role()) is not null'],
    ['therapy_holiday_countries', 'read_countries', '{authenticated}', 'true',
     '(( SELECT current_user_role() AS current_user_role) IS NOT NULL)', '(select public.current_user_role()) is not null'],
    ['therapy_package_rules', 'read therapy rules', '{authenticated}', 'true',
     '(( SELECT current_user_role() AS current_user_role) IS NOT NULL)', '(select public.current_user_role()) is not null'],
    ['therapy_package_services', 'read therapy package services', '{authenticated}', 'true',
     '(( SELECT current_user_role() AS current_user_role) IS NOT NULL)', '(select public.current_user_role()) is not null'],
    ['therapy_package_vouchers', 'read therapy package vouchers', '{authenticated}', 'true',
     '(( SELECT current_user_role() AS current_user_role) IS NOT NULL)', '(select public.current_user_role()) is not null'],
    ['therapy_service_stores', 'read service stores', '{authenticated}', 'true',
     '(( SELECT current_user_role() AS current_user_role) IS NOT NULL)', '(select public.current_user_role()) is not null'],
    ['therapy_services', 'read services', '{authenticated}', 'true',
     '(( SELECT current_user_role() AS current_user_role) IS NOT NULL)', '(select public.current_user_role()) is not null'],
    ['therapy_voucher_component_services', 'read voucher component services', '{authenticated}', 'true',
     '(( SELECT current_user_role() AS current_user_role) IS NOT NULL)', '(select public.current_user_role()) is not null'],
    ['therapy_voucher_components', 'read voucher components', '{authenticated}', 'true',
     '(( SELECT current_user_role() AS current_user_role) IS NOT NULL)', '(select public.current_user_role()) is not null'],
    ['therapy_voucher_definitions', 'read voucher definitions', '{authenticated}', 'true',
     '(( SELECT current_user_role() AS current_user_role) IS NOT NULL)', '(select public.current_user_role()) is not null'],
    ['unlimited_therapy_packages', 'read utp', '{authenticated}', 'true',
     '(( SELECT current_user_role() AS current_user_role) IS NOT NULL)', '(select public.current_user_role()) is not null'],
    ['unlimited_therapy_store_prices', 'read utsp', '{authenticated}', 'true',
     '(( SELECT current_user_role() AS current_user_role) IS NOT NULL)', '(select public.current_user_role()) is not null'],
    ['voucher_redemptions', 'read voucher redemptions', '{authenticated}', 'true',
     '(( SELECT current_user_role() AS current_user_role) IS NOT NULL)', '(select public.current_user_role()) is not null'],
    ['voucher_store_prices', 'read voucher prices', '{authenticated}', 'true',
     '(( SELECT current_user_role() AS current_user_role) IS NOT NULL)', '(select public.current_user_role()) is not null'],
    ['voucher_store_stock', 'read voucher stock', '{authenticated}', 'true',
     '(( SELECT current_user_role() AS current_user_role) IS NOT NULL)', '(select public.current_user_role()) is not null'],
    ['vouchers', 'read vouchers', '{authenticated}', '(deleted_at IS NULL)',
     '((deleted_at IS NULL) AND (( SELECT current_user_role() AS current_user_role) IS NOT NULL))', '(deleted_at is null) and (select public.current_user_role()) is not null'],
    ['warehouses', 'read warehouses', '{authenticated}', 'true',
     '(( SELECT current_user_role() AS current_user_role) IS NOT NULL)', '(select public.current_user_role()) is not null']];
  -- The PDF folder's rules: rule, command, qualifier and check as read on
  -- 9 Oct 2026, and as this leaves them.
  c_pdf constant text[][] := array[
    ['invoice pdfs read', 'SELECT', '(bucket_id = ''invoice-pdfs''::text)', null,
     '((bucket_id = ''invoice-pdfs''::text) AND (is_manager_or_above() OR user_has_store_access(survey_attachment_store(name))))', null],
    ['invoice pdfs insert', 'INSERT', null, '(bucket_id = ''invoice-pdfs''::text)',
     null, '((bucket_id = ''invoice-pdfs''::text) AND (is_manager_or_above() OR user_has_store_access(survey_attachment_store(name))))'],
    ['invoice pdfs update', 'UPDATE', '(bucket_id = ''invoice-pdfs''::text)', '(bucket_id = ''invoice-pdfs''::text)',
     '((bucket_id = ''invoice-pdfs''::text) AND is_owner_or_manager())', '((bucket_id = ''invoice-pdfs''::text) AND is_owner_or_manager())']];
  -- A person's own rows: table, rule and qualifier as read on 9 Oct 2026, the
  -- qualifier as this leaves it, and the new one.
  c_own constant text[][] := array[
    ['approval_requests', 'read approval requests', '((requested_by = auth.uid()) OR is_manager_or_above())',
     '(((requested_by = auth.uid()) AND (( SELECT current_user_role() AS current_user_role) IS NOT NULL)) OR is_manager_or_above())', '((requested_by = auth.uid()) and ((select public.current_user_role()) is not null)) or public.is_manager_or_above()'],
    ['staff_commission_payouts', 'read staff payouts', '(is_manager_or_above() OR (staff_id = auth.uid()))',
     '(is_manager_or_above() OR ((staff_id = auth.uid()) AND (( SELECT current_user_role() AS current_user_role) IS NOT NULL)))', 'public.is_manager_or_above() or ((staff_id = auth.uid()) and ((select public.current_user_role()) is not null))'],
    ['staff_commissions', 'read staff commissions', '(is_manager_or_above() OR (staff_id = auth.uid()))',
     '(is_manager_or_above() OR ((staff_id = auth.uid()) AND (( SELECT current_user_role() AS current_user_role) IS NOT NULL)))', 'public.is_manager_or_above() or ((staff_id = auth.uid()) and ((select public.current_user_role()) is not null))']];
  v_path text := current_setting('search_path');
  v_claims text := current_setting('request.jwt.claims', true);
  r record; v text; v_def text; n int; i int; v_owner uuid;
  v_qual text; v_roles text; v_cmd text; v_check text; v_trg_todo boolean;
begin
  perform set_config('search_path', 'public', true);

  -- ── Guards: nothing changes unless all pass ──────────────────────────────
  if to_regprocedure('public.current_user_role()') is null
     or md5(pg_get_functiondef('public.current_user_role()'::regprocedure)) <> c_role_406 then
    raise exception '407: 406 is not in (current_user_role() is not 406''s version); apply 406 first'; end if;
  foreach v in array array['profile_privilege_change_allowed()', 'is_owner_or_admin()', 'is_manager_or_above()',
                           'is_owner_or_manager()', 'user_has_store_access(uuid)', 'survey_attachment_store(text)'] loop
    if to_regprocedure('public.' || v) is null then
      raise exception '407: public.% is missing', v; end if;
  end loop;
  if md5(pg_get_functiondef('public.profile_privilege_change_allowed()'::regprocedure)) <> '5fa0c10e9eb0c7007e87a2baf5d36264'
     or md5(pg_get_functiondef('public.is_owner_or_admin()'::regprocedure)) <> '3856bdf5ed650fe84e2304ec4f0f0a68'
     or md5(pg_get_functiondef('public.is_manager_or_above()'::regprocedure)) <> 'f12b9ed342070fa4defa30e4da2ba655'
     or md5(pg_get_functiondef('public.is_owner_or_manager()'::regprocedure)) <> '125dec10ce33b84ff5fb40a9bd455235'
     or md5(pg_get_functiondef('public.user_has_store_access(uuid)'::regprocedure)) <> '8c82c6bcb64f496c5a05a2b8dafa95f8'
     or md5(pg_get_functiondef('public.survey_attachment_store(text)'::regprocedure)) <> '58f7d30040f104d240b40ec3e9d9567f' then
    raise exception '407: a helper the new rules call is not the version read on 9 Oct 2026'; end if;

  -- The 47 read rules: as read on 9 Oct (SELECT, that qualifier, those roles),
  -- or already as this leaves them.
  for i in 1 .. array_length(c_rules, 1) loop
    select p.qual, p.roles::text, p.cmd, p.with_check into v_qual, v_roles, v_cmd, v_check
      from pg_policies p where p.schemaname = 'public' and p.tablename = c_rules[i][1] and p.policyname = c_rules[i][2];
    if not found or v_cmd <> 'SELECT' or v_check is not null
       or not ((v_qual = c_rules[i][4] and v_roles = c_rules[i][3])
               or (v_qual = c_rules[i][5] and v_roles = '{authenticated}')) then
      raise exception '407: the rule "%" on public.% is not the one read on 9 Oct 2026 (%, %)',
        c_rules[i][2], c_rules[i][1], v_qual, v_roles; end if;
  end loop;

  -- The PDF folder's three rules.
  for i in 1 .. array_length(c_pdf, 1) loop
    if not exists (select 1 from pg_policies p
                    where p.schemaname = 'storage' and p.tablename = 'objects' and p.policyname = c_pdf[i][1]
                      and p.cmd = c_pdf[i][2] and p.roles = '{authenticated}'
                      and ((p.qual is not distinct from c_pdf[i][3] and p.with_check is not distinct from c_pdf[i][4])
                           or (p.qual is not distinct from c_pdf[i][5] and p.with_check is not distinct from c_pdf[i][6]))) then
      raise exception '407: the storage rule "%" is not the one read on 9 Oct 2026', c_pdf[i][1]; end if;
  end loop;
  -- The three own-row read rules.
  for i in 1 .. array_length(c_own, 1) loop
    if not exists (select 1 from pg_policies p where p.schemaname = 'public' and p.tablename = c_own[i][1]
                    and p.policyname = c_own[i][2] and p.cmd = 'SELECT' and p.roles = '{authenticated}'
                    and p.with_check is null and p.qual in (c_own[i][3], c_own[i][4])) then
      raise exception '407: the rule "%" on public.% is not the one read on 9 Oct 2026', c_own[i][2], c_own[i][1]; end if;
  end loop;
  if not exists (select 1 from storage.buckets where id = 'invoice-pdfs' and not public) then
    raise exception '407: the private invoice-pdfs bucket is missing'; end if;

  -- The approval-request write rules: as read on 9 Oct, or already dropped.
  for r in select * from (values
    ('insert approval requests', 'INSERT', null, '(requested_by = auth.uid())'),
    ('update approval requests', 'UPDATE', 'is_manager_or_above()', 'is_manager_or_above()')
  ) x(pol, cmd, qual_before, check_before)
  loop
    if exists (select 1 from pg_policies p where p.schemaname = 'public' and p.tablename = 'approval_requests'
                and p.policyname = r.pol)
       and not exists (select 1 from pg_policies p where p.schemaname = 'public' and p.tablename = 'approval_requests'
                and p.policyname = r.pol and p.cmd = r.cmd and p.roles = '{authenticated}'
                and p.qual is not distinct from r.qual_before and p.with_check is not distinct from r.check_before) then
      raise exception '407: the rule "%" on approval_requests is not the one read on 9 Oct 2026', r.pol; end if;
  end loop;

  -- "update profiles".
  if not exists (select 1 from pg_policies p where p.schemaname = 'public' and p.tablename = 'profiles'
                  and p.policyname = 'update profiles' and p.cmd = 'UPDATE' and p.roles = '{authenticated}'
                  and ((p.qual = c_upd_before and p.with_check = c_upd_before)
                       or (p.qual = c_upd_after and p.with_check = c_upd_after))) then
    raise exception '407: the rule "update profiles" is not the one read on 9 Oct 2026'; end if;

  -- The profile guard trigger and its function.
  if not exists (select 1 from pg_trigger t where t.tgrelid = 'public.profiles'::regclass
                  and t.tgname = 'guard_profile_privileges' and not t.tgisinternal and t.tgenabled = 'O'
                  and t.tgfoid = 'public.trg_guard_profile_privileges()'::regprocedure
                  and pg_get_triggerdef(t.oid) like '%BEFORE UPDATE ON public.profiles FOR EACH ROW%') then
    raise exception '407: the trigger guard_profile_privileges is not on public.profiles, before update'; end if;
  v_def := pg_get_functiondef('public.trg_guard_profile_privileges()'::regprocedure);
  if md5(v_def) = c_trg_after then
    v_trg_todo := false;
  elsif md5(v_def) = c_trg_before then
    v_trg_todo := true;
    n := (length(v_def) - length(replace(v_def, c_trg_anchor, ''))) / length(c_trg_anchor);
    if n <> 1 then raise exception '407: the trigger function''s anchor occurs % times', n; end if;
    v_def := replace(v_def, c_trg_anchor, c_trg_repl);
    if md5(v_def) <> c_trg_after then
      raise exception '407: the trigger function built is not the one tested (md5 %)', md5(v_def); end if;
  else
    raise exception '407: public.trg_guard_profile_privileges() is not the version read on 9 Oct 2026 (md5 %)', md5(v_def);
  end if;

  -- ── Change ───────────────────────────────────────────────────────────────
  for i in 1 .. array_length(c_rules, 1) loop
    execute format('alter policy %I on public.%I to authenticated using (%s)', c_rules[i][2], c_rules[i][1], c_rules[i][6]);
  end loop;
  alter policy "invoice pdfs read" on storage.objects
    using ((bucket_id = 'invoice-pdfs') and (public.is_manager_or_above() or public.user_has_store_access(public.survey_attachment_store(name))));
  alter policy "invoice pdfs insert" on storage.objects
    with check ((bucket_id = 'invoice-pdfs') and (public.is_manager_or_above() or public.user_has_store_access(public.survey_attachment_store(name))));
  alter policy "invoice pdfs update" on storage.objects
    using ((bucket_id = 'invoice-pdfs') and public.is_owner_or_manager())
    with check ((bucket_id = 'invoice-pdfs') and public.is_owner_or_manager());
  for i in 1 .. array_length(c_own, 1) loop
    execute format('alter policy %I on public.%I using (%s)', c_own[i][2], c_own[i][1], c_own[i][5]);
  end loop;
  update storage.buckets set file_size_limit = c_mb, allowed_mime_types = array['application/pdf']
   where id = 'invoice-pdfs'
     and (file_size_limit is distinct from c_mb or allowed_mime_types is distinct from array['application/pdf']);

  if exists (select 1 from pg_policies p where p.schemaname = 'public' and p.tablename = 'approval_requests'
              and p.policyname = 'insert approval requests') then
    drop policy "insert approval requests" on public.approval_requests;
  end if;
  if exists (select 1 from pg_policies p where p.schemaname = 'public' and p.tablename = 'approval_requests'
              and p.policyname = 'update approval requests') then
    drop policy "update approval requests" on public.approval_requests;
  end if;
  revoke all on table public.approval_requests, public.audit_logs, public.document_sends from anon;
  revoke insert, update, delete, truncate, references, trigger, maintain
    on table public.approval_requests, public.audit_logs, public.document_sends from authenticated;

  alter policy "update profiles" on public.profiles
    using (((id = auth.uid()) and (public.current_user_role() is not null)) or public.is_owner_or_admin() or ((public.current_user_role() = 'manager') and (role = any (array['inventory_manager', 'staff']::public.user_role[]))))
    with check (((id = auth.uid()) and (public.current_user_role() is not null)) or public.is_owner_or_admin() or ((public.current_user_role() = 'manager') and (role = any (array['inventory_manager', 'staff']::public.user_role[]))));
  if v_trg_todo then execute v_def; end if;

  -- ── As tested ────────────────────────────────────────────────────────────
  for i in 1 .. array_length(c_rules, 1) loop
    if not exists (select 1 from pg_policies p where p.schemaname = 'public' and p.tablename = c_rules[i][1]
                    and p.policyname = c_rules[i][2] and p.qual = c_rules[i][5] and p.roles = '{authenticated}') then
      raise exception '407: the rule "%" on public.% is not as tested', c_rules[i][2], c_rules[i][1]; end if;
  end loop;
  for i in 1 .. array_length(c_pdf, 1) loop
    if not exists (select 1 from pg_policies p where p.schemaname = 'storage' and p.tablename = 'objects'
                    and p.policyname = c_pdf[i][1] and p.qual is not distinct from c_pdf[i][5]
                    and p.with_check is not distinct from c_pdf[i][6]) then
      raise exception '407: the storage rule "%" is not as tested', c_pdf[i][1]; end if;
  end loop;
  for i in 1 .. array_length(c_own, 1) loop
    if not exists (select 1 from pg_policies p where p.schemaname = 'public' and p.tablename = c_own[i][1]
                    and p.policyname = c_own[i][2] and p.qual = c_own[i][4] and p.roles = '{authenticated}') then
      raise exception '407: the rule "%" on public.% is not as tested', c_own[i][2], c_own[i][1]; end if;
  end loop;
  if not exists (select 1 from pg_policies p where p.schemaname = 'public' and p.tablename = 'profiles'
                  and p.policyname = 'update profiles' and p.qual = c_upd_after and p.with_check = c_upd_after) then
    raise exception '407: "update profiles" is not as tested'; end if;
  if exists (select 1 from pg_policies p where p.schemaname = 'public' and p.tablename = 'approval_requests'
              and p.cmd <> 'SELECT') then
    raise exception '407: approval_requests still has a write rule'; end if;
  if md5(pg_get_functiondef('public.trg_guard_profile_privileges()'::regprocedure)) <> c_trg_after then
    raise exception '407: the trigger function is not as tested'; end if;
  if (select file_size_limit from storage.buckets where id = 'invoice-pdfs') is distinct from c_mb
     or (select allowed_mime_types from storage.buckets where id = 'invoice-pdfs') is distinct from array['application/pdf'] then
    raise exception '407: the invoice-pdfs limits did not take'; end if;
  foreach v in array array['approval_requests', 'audit_logs', 'document_sends'] loop
    if has_table_privilege('anon', 'public.' || v, 'select,insert,update,delete,truncate,references,trigger,maintain')
       or has_table_privilege('authenticated', 'public.' || v, 'insert,update,delete,truncate,references,trigger,maintain')
       or not has_table_privilege('authenticated', 'public.' || v, 'select')
       or not has_table_privilege('service_role', 'public.' || v, 'select,insert,update,delete') then
      raise exception '407: the grants on public.% are not as tested', v; end if;
  end loop;

  -- ── Behaviour, switching role (nothing is printed, no row changes) ───────
  perform set_config('request.jwt.claims',
    json_build_object('sub', gen_random_uuid(), 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  for i in 1 .. array_length(c_rules, 1) loop
    execute format('select count(*) from public.%I', c_rules[i][1]) into n;
    if n > 0 then raise exception '407: a login with no profile still reads public.%', c_rules[i][1]; end if;
  end loop;
  select count(*) into n from storage.objects where bucket_id = 'invoice-pdfs';
  if n > 0 then raise exception '407: a login with no profile still sees the invoice PDFs'; end if;
  begin
    insert into public.approval_requests (request_type, status) values ('adjustment', 'pending');
    raise exception '407: a signed-in login can still insert an approval request';
  exception when insufficient_privilege then null;
  end;
  execute 'reset role';
  select p.id into v_owner from public.profiles p
   where p.role = 'owner' and p.is_active and p.deleted_at is null
     and coalesce(p.invitation_status, 'accepted') = 'accepted'
   order by p.created_at limit 1;
  if v_owner is not null then
    perform set_config('request.jwt.claims',
      json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    perform count(*) from public.products;
    perform count(*) from public.stores;
    perform count(*) from storage.objects where bucket_id = 'invoice-pdfs';
    execute 'reset role';
  end if;
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);

  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $mig$;
