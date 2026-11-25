-- 539_customer_export_and_staff_contacts_for_owners_and_managers.sql
--
-- ONLY AN OWNER OR A MANAGER EXPORTS THE CUSTOMER LIST, AND EACH EXPORT IS IN THE AUDIT LOG; A
-- CUSTOMER LIST GIVES ANYONE ELSE AT MOST 50 CUSTOMERS AT A TIME; AN INVENTORY MANAGER GETS NO
-- CUSTOMER LIST; A COLLEAGUE'S LOGIN EMAIL, PERSONAL PHONE AND PERSONAL EMAIL ARE AN OWNER'S, A
-- MANAGER'S AND THEIR OWN
--
--   From the security audit of 17 Nov 2026 (finding M13; business rules R5 and R6). The BEFORE md5s
--   and the relied-on md5s below are those of production after 538 (head 20261125104023, function
--   fingerprint 8a674d648346f9f57409686cb4ca5022/1457). If production differs when this is applied,
--   it refuses and changes nothing.
--   (The number 539 is this file's name and its errors' prefix; if it changes at commit, change it
--   there, in the 539 comments it writes into the functions below (and so their AFTER md5s, also in
--   scripts/customers/undo-539.sql and in the suites that know them), and in the name and path of
--   its suite.)
--
-- GO-LIVE ORDER: THE PAGES FIRST, THEN THIS (as 514 and 515). Pages from before 539 read
--   public.profiles with select('*') (the sign-in itself, Users & Roles, a store's staff list);
--   once a signed-in login reads only nine columns that read fails for every role, and a fresh
--   load ends in the app's connection error. The pages of 539 name their columns and work before
--   and after it (see the suite's notes). A browser tab opened before the new pages keeps its
--   signed-in profile until it reloads (a failed re-read keeps what is loaded); in it, Users &
--   Roles and a store's staff list fail to load until it reloads.
--
-- WHAT WAS WRONG
--
--   Every staff role, Inventory Manager included, at any store, reads the whole customer database:
--   the customers table's read rule is "any staff role", search_customers (398, 418) answers any
--   staff login with no upper page size (search_customers('', null, 100000, 0) gives everyone), as
--   does the Therapy page's customer summary (therapy_customer_summary), and both Excel exports on
--   the Customers page ("Export" and "Special Export": name, phone, email, date of birth, gender,
--   occupation, address, notes) are shown to every role, with no record of who exported what. And
--   every staff login reads every colleague's login email, personal phone and personal email from
--   public.profiles; anon holds every table privilege on it. Every staff role reads every
--   customer's past phones (customer_phone_history).
--
-- THE RULE (the user, 25 Nov 2026)
--
--   1. Export: only an Owner or a Manager exports the customer list, in the page and on the
--      server; each export writes one Audit Log entry: who, when, how many customers, which
--      filters. An Admin is not an Owner or a Manager.
--   2. Staff searches: staff keep finding and opening any customer as now (the pages' direct reads
--      of a customer stay), but a customer list (search_customers, the Therapy page's summary, the
--      Health Surveys customer list) gives anyone but an Owner or a Manager at most 50 customers a
--      call. Owners and Managers are unchanged. An Inventory Manager gets no customer list: neither
--      the customers table's read rule, nor the phone history's, nor those lists, nor the
--      invoice's affiliate picker (active_affiliates_for_picker) answers them.
--   3. Colleagues' contact details: a colleague's login email, personal phone and personal email
--      are seen only by an Owner or a Manager, and by the person themselves. Everyone else sees
--      names, roles, work phones and the other columns.
--   4. Health answers stay readable across stores (R6): nothing here touches them.
--   5. "Stock only" for Inventory Managers (25 Nov 2026): no invoices and no customer data at all.
--      539 closes their customer list (2 above); their invoice roads (writes, invoice reads, the
--      functions that name customers on invoices, therapy benefits, the print and send log) are
--      540's, which goes live in the same window.
--
-- WHAT THIS DOES (every role refusal is errcode 42501, in the words the pages show)
--
--   * A helper only postgres can call, customer_list_guard(page size): for an Inventory Manager,
--     "An Inventory Manager does not see the customer list."; for anyone else but an Owner or a
--     Manager, a page size above 50 (a missing one is 50), "A search returns at most 50 customers
--     at a time."; for an Owner, a Manager, a login that is not staff and the secret key, nothing.
--     Its callers run it first, as a statement of its own, and are otherwise word for word as
--     before (what each finds and in what order):
--       search_customers (the Customers page's list; a login that is not staff and the secret key
--         still get no rows);
--       therapy_customer_summary (the Therapy page's customers);
--       customer_survey_overview (Health Surveys' customers: an Owner and a Manager keep 200 a
--         page, as 406 set; Staff and an Admin 50; an Inventory Manager was refused already);
--       active_affiliates_for_picker() (the invoice's affiliate picker, unpaged: only the
--         Inventory Manager's refusal applies; Staff keep it).
--   * The customers table's past phones, customer_phone_history: its read rule "read phone
--     history" names the same four roles; an Inventory Manager reads no row (the Customers page's
--     Profile, the only page that reads it, is not theirs).
--   * The customers table's read rule "read customers" names the staff roles that read it:
--     (deleted_at is null) and the caller's role is an Owner, an Admin, a Manager or Staff. An
--     Inventory Manager reads no customer row; nothing else changes.
--   * A new function for the Customers page's two exports, export_customers(export, search,
--     source, visited, first visit from, first visit to, created from, created to): an active Owner
--     or Manager only (require_active_staff() and current_user_role(); anyone else, an Admin and
--     the secret key included: "Only an Owner or a Manager can export the customer list."). It
--     returns every customer search_customers finds for those filters, in its order, as ONE jsonb
--     value ({customers: n, rows: [...]}; a set would be cut at the API's row limit with no
--     error), and in the same call writes one Audit Log entry, customers_exported (module
--     customers, table customers): who and when (changed_by, actor_role, created_at), how many
--     customers it returned, and the filters (the search, the source, visited, the first-visit
--     dates and the created dates the person chose; the page keeps applying the created dates
--     itself, as before), and nothing of the customers. export is 'standard' or 'special' ("An
--     export is the standard export or the Special Export.").
--   * public.profiles: a signed-in login (authenticated) keeps reading the rows it read (the rule
--     "read profiles" is unchanged), but only the columns id, full_name, role, is_active,
--     deleted_at, created_at, updated_at, work_phone and invitation_status: its table-wide SELECT
--     is replaced by a SELECT on those nine columns. anon loses its table-wide SELECT and has
--     none (no rule ever let it read a row). email, personal_phone and personal_email are read
--     through functions owned by postgres:
--       user_admin_list() (the Users & Roles page): now gives the three only to an Owner or a
--         Manager, and to each person for their own row; an Admin gets them empty for others
--         (everything else in it as before);
--       my_profile_contact_details(): the caller's own login email, personal phone and personal
--         email (active staff only, as every staff function since 406; none for the secret key).
--         No page needs it today (the sign-in takes the login email from the session).
--     Updating a profile is unchanged (the table-wide UPDATE, the rule "update profiles", the
--     guard trigger and 532's audit trigger, all postgres-owned definers): a page asks back only
--     columns it may read (the Users & Roles page asks for id and is_active).
--
-- WHAT STAYS
--
--   * Staff and Admins still find and open any customer, of any store, as now: the pages' direct
--     reads of a customer (the invoice picker, a customer's name and phone on an invoice, an event
--     guest, a survey, an affiliate, a report) and the functions the pages call (customer_overview
--     and the others). A Staff login used outside the app can still read the whole list (the
--     user's decision): through search_customers 50 at a time, paging on; and straight from the
--     customers table, which is not capped (only the API's Max rows per request limits one read,
--     and they page on).
--   * The export's Audit Log entry is written by export_customers only: an Owner or a Manager can
--     still read the whole list with no entry, through the search at any size or the table.
--   * The search words are kept in the entry as a filter, so a name or number typed there is in
--     the Audit Log.
--   * Until a later step removes it (after 539 is live), the Customers page falls back to the old
--     export, page by page through search_customers with no entry, when export_customers is
--     missing: a schema cache not yet reloaded, or a tab still on the pages of before 539,
--     exports the old way, with no entry, until it reloads.
--   * An Owner's and a Manager's searches, the customer list's order, and every customer column.
--   * The other lists of customers: invoice_list_page and therapy_list_page (200 a page, by store)
--     and referrer_list(), as they are. Until 540, an Inventory Manager still reads what the
--     invoice functions and other functions asking only for an active staff login give
--     (customer_overview, affiliate_directory, therapy_customer_detail, report_pricing and others:
--     540's list), and makes and reads invoices of their stores.
--   * The secret key: search_customers still gives it nothing (it is not a staff login); the
--     server's own work reads public.profiles and public.customers as before.
--   * Health answers across stores (R6).
--   * An Owner, an Admin and a Manager still read invitees' email, personal phone and personal
--     email in user_invitations, and the old and new values in the Audit Log's profile entries
--     (staff_profile_*); Owners and Managers may by decision, and no Admin exists on production.
--   * anon keeps its other table privileges on public.profiles; no rule lets anon write a row.
--   * A column added to public.profiles later is not readable by a signed-in login until it is
--     granted (grant select (column) on public.profiles to authenticated).
--   * A browser tab opened before the pages of 539 keeps working until it reloads (see the order).
--
-- UNDO
--
--   scripts/customers/undo-539.sql (it refuses unless every function, rule and grant here
--   is exactly 539's and nothing else calls the new functions): puts the five functions back
--   exactly as they were, the two read rules as they were, the table-wide SELECT on
--   public.profiles back for authenticated and anon (and the nine column grants off), and drops
--   export_customers, my_profile_contact_details and customer_list_guard. The Audit Log keeps its customers_exported entries (it
--   keeps every entry, 536). Put back the pages of before 539 after the undo, not before: the
--   pages of 539 work on both. A later migration changing any of these must pin 539's AFTER md5.
--
-- NO SELF-TEST INSIDE; the suite is scripts/customers/tests/customer-list-and-staff-contacts-539.sql.
--
-- One transaction with its history row, by the usual wrapper; nothing else is written.

do $mig$
declare
  -- Functions the patched and new ones rely on, as tested: the caller's role and active-staff
  -- check, the audit writer, the first visits search_customers reads, the profile triggers.
  c_relied constant text[] := array[
    'current_user_role()',
    'require_active_staff(text[])',
    'write_audit_ex(text,uuid,text,jsonb,jsonb,text,text,uuid,text,text)',
    'customer_centre_visits()',
    'trg_guard_profile_privileges()',
    'trg_audit_direct_change()'];
  c_relied_md5 constant text[] := array[
    '519b0a33a3548f970c5d585b6e76a389',
    '877b3aa74cea559881979bb161c450e2',
    'c705c733e213a27f0dc32d54322cc855',
    'c07a5a0cbbf52ba45e5dc911b20002da',
    '7a45127fc3f23b627285a6c5f90dbb6d',
    '5dcea97b6479d9bb6a53adfa9dfbcba4'];
  -- The functions patched, BEFORE and AFTER, with their grants (unchanged).
  c_sig constant text[] := array[
    'search_customers(text,text,integer,integer,text,date,date)',
    'therapy_customer_summary(text,integer,integer,boolean)',
    'customer_survey_overview(text,text,integer,integer)',
    'active_affiliates_for_picker()',
    'user_admin_list()'];
  c_before constant text[] := array[
    'a7403700638459c6567a039ddab398f9',
    'af030b297c6ab5dc2c64bde101722279',
    'd0301231179b3d05107e3309264692ff',
    '95316cbb02a3ecc6c078c8b877b14d6d',
    '4d770ec592c3e96644602f196b4f7ce2'];
  c_after constant text[] := array['25f9a33395ad17f7d6b8f63252bd34ab', '93c046a23c15684aa88a67b2dd3f5c34', '42b98e0787c27efa66f4b32c0272c8dc', 'a75fa8c401202112d4abf0b478b0e59a', 'ab6167ddfea14ecc4b1140ce4221a0d4'];
  c_acl constant text := 'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres';
  -- The patches, each found exactly once in its function (1 search_customers,
  -- 2 therapy_customer_summary, 3 customer_survey_overview, 4 active_affiliates_for_picker,
  -- 5 user_admin_list: the login email, then the personal phone and email).
  c_fn constant int[] := array[1, 2, 3, 4, 5, 5];
  c_anchor constant text[] := array[
$a$AS $function$
  -- 398: the Customers page's list$a$,
$a$  select public.require_active_staff();  -- 406: active staff only
  with vouchers as ($a$,
$a$  select public.require_active_staff('{owner,admin,manager,staff}');  -- 406: active staff only; 419: not Inventory Managers (health data)
$a$,
$a$  select public.require_active_staff();  -- 406: active staff only
  select a.id, a.customer_id, c.full_name, c.phone, a.store_id$a$,
$a$  select p.id, p.full_name, p.email, p.role, p.is_active, p.invitation_status,$a$,
$a$         p.work_phone, p.personal_phone, p.personal_email,$a$];
  c_new constant text[] := array[
$n$AS $function$
  -- 539 (security audit of 17 Nov 2026, M13; the user, 25 Nov 2026): an Inventory Manager gets no
  -- customer list, and anyone but an Owner or a Manager at most 50 customers a call (they page on).
  select public.customer_list_guard(p_limit);
  -- 398: the Customers page's list$n$,
$n$  select public.require_active_staff();  -- 406: active staff only
  -- 539 (security audit of 17 Nov 2026, M13): no Inventory Manager; at most 50 a call but for an
  -- Owner or a Manager.
  select public.customer_list_guard(p_limit);
  with vouchers as ($n$,
$n$  select public.require_active_staff('{owner,admin,manager,staff}');  -- 406: active staff only; 419: not Inventory Managers (health data)
  -- 539 (security audit of 17 Nov 2026, M13): at most 50 a call but for an Owner or a Manager
  -- (who keep 200, below).
  select public.customer_list_guard(p_limit);
$n$,
$n$  select public.require_active_staff();  -- 406: active staff only
  -- 539 (security audit of 17 Nov 2026, M13): no Inventory Manager (no customer list for them).
  select public.customer_list_guard(null);
  select a.id, a.customer_id, c.full_name, c.phone, a.store_id$n$,
$n$  -- 539 (security audit of 17 Nov 2026, M13; the user, 25 Nov 2026): the login email, personal
  -- phone and personal email for an Owner or a Manager, and for each person their own; empty
  -- for anyone else (an Admin).
  select p.id, p.full_name,
         case when public.current_user_role() in ('owner', 'manager') or p.id = auth.uid() then p.email end,
         p.role, p.is_active, p.invitation_status,$n$,
$n$         p.work_phone,
         case when public.current_user_role() in ('owner', 'manager') or p.id = auth.uid() then p.personal_phone end,
         case when public.current_user_role() in ('owner', 'manager') or p.id = auth.uid() then p.personal_email end,$n$];
  -- The customers table's read rule, before and after (as pg_get_expr prints them).
  c_pol_before constant text := '((deleted_at IS NULL) AND (( SELECT current_user_role() AS current_user_role) IS NOT NULL))';
  c_pol_src constant text := '(deleted_at is null) and ((select public.current_user_role()) = any (array[''owner'', ''admin'', ''manager'', ''staff'']::public.user_role[]))';
  c_pol_after constant text := '((deleted_at IS NULL) AND (( SELECT current_user_role() AS current_user_role) = ANY (ARRAY[''owner''::user_role, ''admin''::user_role, ''manager''::user_role, ''staff''::user_role])))';
  -- customer_phone_history's read rule, before and after.
  c_ph_before constant text := '(( SELECT current_user_role() AS current_user_role) IS NOT NULL)';
  c_ph_src constant text := '((select public.current_user_role()) = any (array[''owner'', ''admin'', ''manager'', ''staff'']::public.user_role[]))';
  c_ph_after constant text := '(( SELECT current_user_role() AS current_user_role) = ANY (ARRAY[''owner''::user_role, ''admin''::user_role, ''manager''::user_role, ''staff''::user_role]))';
  -- public.profiles: its columns, its grants before and after, the nine columns signed-in logins
  -- read, and its two rules (unchanged, relied on).
  c_prof_cols constant text := 'id uuid|full_name text|email text|role user_role|is_active boolean|deleted_at timestamp with time zone|created_at timestamp with time zone|updated_at timestamp with time zone|personal_phone text|work_phone text|personal_email text|invitation_status text';
  c_prof_acl_before constant text := 'anon=arwdDxtm/postgres,authenticated=arwdDxtm/postgres,postgres=arwdDxtm/postgres,service_role=arwdDxtm/postgres';
  c_prof_acl_after constant text := 'anon=awdDxtm/postgres,authenticated=awdDxtm/postgres,postgres=arwdDxtm/postgres,service_role=arwdDxtm/postgres';
  c_prof_read constant text[] := array['id', 'full_name', 'role', 'is_active', 'deleted_at', 'created_at', 'updated_at', 'work_phone', 'invitation_status'];
  c_prof_hidden constant text[] := array['email', 'personal_phone', 'personal_email'];
  c_prof_pol constant text :=
    'read profiles|r|((id = ( SELECT auth.uid() AS uid)) OR (( SELECT current_user_role() AS current_user_role) IS NOT NULL))|-'
    || E'\n' || 'update profiles|w|(((id = ( SELECT auth.uid() AS uid)) AND (( SELECT current_user_role() AS current_user_role) IS NOT NULL)) OR ( SELECT is_owner_or_admin() AS is_owner_or_admin) OR ((( SELECT current_user_role() AS current_user_role) = ''manager''::user_role) AND (role = ANY (ARRAY[''inventory_manager''::user_role, ''staff''::user_role]))))|(((id = ( SELECT auth.uid() AS uid)) AND (( SELECT current_user_role() AS current_user_role) IS NOT NULL)) OR ( SELECT is_owner_or_admin() AS is_owner_or_admin) OR ((( SELECT current_user_role() AS current_user_role) = ''manager''::user_role) AND (role = ANY (ARRAY[''inventory_manager''::user_role, ''staff''::user_role]))))';
  -- The new functions: their signatures, text and grants (the helpers postgres's alone, made first:
  -- the patched functions call the guard).
  c_new_sig constant text[] := array[
    'customer_list_guard(integer)',
    'export_customers(text,text,text,text,date,date,date,date)',
    'my_profile_contact_details()'];
  c_new_def constant text[] := array[
$d$CREATE OR REPLACE FUNCTION public.customer_list_guard(p_limit integer)
 RETURNS void
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_role public.user_role := public.current_user_role();
begin
  -- 539 (security audit of 17 Nov 2026, M13; the user, 25 Nov 2026): run first by every list of
  -- customers a page calls. An Inventory Manager gets no customer list; anyone else but an Owner
  -- or a Manager gets at most 50 customers a call (a missing page size is 50). An Owner, a
  -- Manager, a login that is not staff and the secret key pass (each list's own test follows).
  if v_role = 'inventory_manager' then
    raise exception 'An Inventory Manager does not see the customer list.' using errcode = '42501';
  end if;
  if v_role is not null and v_role not in ('owner', 'manager') and coalesce(p_limit, 50) > 50 then
    raise exception 'A search returns at most 50 customers at a time.' using errcode = '42501';
  end if;
end
$function$
$d$,
$d$CREATE OR REPLACE FUNCTION public.export_customers(p_export text, p_query text DEFAULT NULL::text, p_source text DEFAULT NULL::text, p_visited text DEFAULT NULL::text, p_visit_from date DEFAULT NULL::date, p_visit_to date DEFAULT NULL::date, p_created_from date DEFAULT NULL::date, p_created_to date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_rows jsonb; v_n integer;
begin
  -- 539 (security audit of 17 Nov 2026, M13; the user, 25 Nov 2026: "Only an Owner or a Manager
  -- may export the customer list"): the Customers page's Export and Special Export. Every customer
  -- search_customers finds for these filters, in its order, as one value (a set would be cut at
  -- the API's row limit), and one Audit Log entry (customers_exported): who and when, how many
  -- customers it returned, and the filters, nothing of the customers. The created dates are
  -- applied by the page, as before; they are recorded as chosen.
  perform public.require_active_staff();
  if public.current_user_role() is null or public.current_user_role() not in ('owner', 'manager') then
    raise exception 'Only an Owner or a Manager can export the customer list.' using errcode = '42501';
  end if;
  if p_export is null or p_export not in ('standard', 'special') then
    raise exception 'An export is the standard export or the Special Export.';
  end if;
  select coalesce(jsonb_agg(to_jsonb(s) - 'total_count' - 'ordinality' order by s.ordinality), '[]'::jsonb), count(*)
    into v_rows, v_n
    from public.search_customers(p_query, p_source, 2147483647, 0, p_visited, p_visit_from, p_visit_to) with ordinality s;
  perform public.write_audit_ex('customers', null, 'customers_exported', null,
    jsonb_build_object('export', p_export, 'customers', v_n,
      'filters', jsonb_build_object(
        'search', nullif(btrim(coalesce(p_query, '')), ''), 'source', nullif(p_source, ''),
        'visited', nullif(p_visited, ''), 'first_visit_from', p_visit_from, 'first_visit_to', p_visit_to,
        'created_from', p_created_from, 'created_to', p_created_to)),
    'customers');
  return jsonb_build_object('customers', v_n, 'rows', v_rows);
end
$function$
$d$,
$d$CREATE OR REPLACE FUNCTION public.my_profile_contact_details()
 RETURNS TABLE(id uuid, email text, personal_phone text, personal_email text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- 539 (security audit of 17 Nov 2026, M13; the user, 25 Nov 2026): the caller's own login
  -- email, personal phone and personal email, which a signed-in login no longer reads from
  -- public.profiles (it reads nine other columns there). Only the caller's own row, for active
  -- staff (406); none for the secret key.
  select public.require_active_staff();  -- 406: active staff only
  select p.id, p.email, p.personal_phone, p.personal_email
    from public.profiles p
   where p.id = auth.uid()
$function$
$d$];
  c_new_md5 constant text[] := array['de5cfaa12b667a4df0d45721b9531141', '1d0eb73a09a49a939f353582844c1fd5', '6ae2834b13b1ab52653da4cf342b99df'];
  c_new_acl constant text[] := array[
    'postgres=X/postgres',
    'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres',
    'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres'];

  v_path text := current_setting('search_path');
  v_lock text := current_setting('lock_timeout');
  v_def text[] := array_fill(null::text, array[5]);
  v_done int := 0; v_new_done int := 0; v_pol_done boolean; v_ph_done boolean; v_prof_done boolean;
  v_have text; d text; i int;
begin
  -- Definitions are read and compared with public alone on the search path.
  perform set_config('search_path', 'public', true);
  -- A busy function or table waits 5 seconds at most, then this refuses whole.
  perform set_config('lock_timeout', '5s', true);

  -- 1. Checks: nothing is changed before all of them pass
  for i in 1 .. cardinality(c_relied) loop
    if to_regprocedure('public.' || c_relied[i]) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i]))) <> c_relied_md5[i] then
      raise exception '539: public.% is missing or not the version this was tested against. Re-read it and re-test before applying.', c_relied[i];
    end if;
  end loop;
  if to_regclass('public.customers') is null or to_regclass('public.profiles') is null or to_regclass('public.audit_logs') is null
     or to_regclass('public.customer_phone_history') is null then
    raise exception '539: a table it uses (customers, profiles, audit_logs, customer_phone_history) is missing'; end if;
  -- The patched functions: BEFORE or AFTER, with their grants.
  for i in 1 .. cardinality(c_sig) loop
    if to_regprocedure('public.' || c_sig[i]) is null then raise exception '539: public.% is missing', c_sig[i]; end if;
    d := pg_get_functiondef(to_regprocedure('public.' || c_sig[i]));
    if (select coalesce(string_agg(x::text, ',' order by x::text), '')
          from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig[i])) is distinct from c_acl then
      raise exception '539: the grants of public.% are not the tested ones. Re-read them before applying.', c_sig[i]; end if;
    if md5(d) = c_after[i] then
      v_done := v_done + 1;
    elsif md5(d) = c_before[i] then
      v_def[i] := d;
    else
      raise exception '539: public.% is not the version this was tested against (md5 %). Re-read it and re-test before applying.', c_sig[i], md5(d);
    end if;
  end loop;
  -- The customers table's read rule: before or after, and the only rule that reads it.
  if (select count(*) from pg_policy p where p.polrelid = 'public.customers'::regclass and p.polcmd in ('r', '*')) <> 1
     or not exists (select 1 from pg_policy p where p.polrelid = 'public.customers'::regclass and p.polname = 'read customers'
                     and p.polcmd = 'r' and p.polpermissive and p.polroles = array['authenticated'::regrole::oid]
                     and pg_get_expr(p.polqual, p.polrelid) in (c_pol_before, c_pol_after)) then
    raise exception '539: the read rule of public.customers is not the one this was tested against. Re-read it before applying.'; end if;
  v_pol_done := (select pg_get_expr(p.polqual, p.polrelid) from pg_policy p
                  where p.polrelid = 'public.customers'::regclass and p.polname = 'read customers') = c_pol_after;
  -- customer_phone_history's read rule: before or after, and the only rule that reads it.
  if (select count(*) from pg_policy p where p.polrelid = 'public.customer_phone_history'::regclass and p.polcmd in ('r', '*')) <> 1
     or not exists (select 1 from pg_policy p where p.polrelid = 'public.customer_phone_history'::regclass and p.polname = 'read phone history'
                     and p.polcmd = 'r' and p.polpermissive and p.polroles = array['authenticated'::regrole::oid]
                     and pg_get_expr(p.polqual, p.polrelid) in (c_ph_before, c_ph_after)) then
    raise exception '539: the read rule of public.customer_phone_history is not the one this was tested against. Re-read it before applying.'; end if;
  v_ph_done := (select pg_get_expr(p.polqual, p.polrelid) from pg_policy p
                 where p.polrelid = 'public.customer_phone_history'::regclass and p.polname = 'read phone history') = c_ph_after;
  -- public.profiles: its columns, its rules, and its grants (before or after).
  select string_agg(a.attname || ' ' || format_type(a.atttypid, a.atttypmod), '|' order by a.attnum) into v_have
    from pg_attribute a where a.attrelid = 'public.profiles'::regclass and a.attnum > 0 and not a.attisdropped;
  if v_have is distinct from c_prof_cols then
    raise exception '539: the columns of public.profiles are not the tested ones (%). Re-read them before applying.', v_have; end if;
  select string_agg(p.polname || '|' || p.polcmd::text || '|' || coalesce(pg_get_expr(p.polqual, p.polrelid), '-') || '|'
                    || coalesce(pg_get_expr(p.polwithcheck, p.polrelid), '-'), E'\n' order by p.polname) into v_have
    from pg_policy p where p.polrelid = 'public.profiles'::regclass;
  if v_have is distinct from c_prof_pol then
    raise exception '539: the rules of public.profiles are not the tested ones. Re-read them before applying.'; end if;
  select coalesce(string_agg(x::text, ',' order by x::text), '') into v_have
    from pg_class c, unnest(c.relacl) x where c.oid = 'public.profiles'::regclass;
  if v_have = c_prof_acl_before
     and not exists (select 1 from pg_attribute a where a.attrelid = 'public.profiles'::regclass and a.attnum > 0 and a.attacl is not null) then
    v_prof_done := false;
  elsif v_have = c_prof_acl_after
     and (select string_agg(a.attname, ',' order by a.attname) from pg_attribute a
           where a.attrelid = 'public.profiles'::regclass and a.attnum > 0 and a.attacl::text = '{authenticated=r/postgres}')
         = (select string_agg(x, ',' order by x) from unnest(c_prof_read) x)
     and (select count(*) from pg_attribute a where a.attrelid = 'public.profiles'::regclass and a.attnum > 0 and a.attacl is not null)
         = cardinality(c_prof_read) then
    v_prof_done := true;
  else
    raise exception '539: the grants on public.profiles are not the tested ones (%). Re-read them before applying.', v_have; end if;
  -- The new functions: missing, or exactly 539's; and no other function of those names.
  for i in 1 .. cardinality(c_new_sig) loop
    if to_regprocedure('public.' || c_new_sig[i]) is not null then
      if md5(pg_get_functiondef(to_regprocedure('public.' || c_new_sig[i]))) <> c_new_md5[i] then
        raise exception '539: a function public.% is there, but not 539''s. Re-read it before applying.', c_new_sig[i]; end if;
      v_new_done := v_new_done + 1;
    end if;
  end loop;
  if exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace
              and p.proname in ('customer_list_guard', 'export_customers', 'my_profile_contact_details')
              and p.oid::regprocedure::text not in (select x from unnest(c_new_sig) x)) then
    raise exception '539: another function of one of 539''s names is there. Re-read it before applying.'; end if;
  if v_done = cardinality(c_sig) and v_pol_done and v_ph_done and v_prof_done and v_new_done = cardinality(c_new_sig) then
    raise exception '539 is already in on this database; nothing was changed.'; end if;
  if v_done > 0 or v_pol_done or v_ph_done or v_prof_done or v_new_done > 0 then
    raise exception '539: only part of it is in on this database (% of % functions patched, customers rule %, phone history rule %, profiles grants %, % of % new functions). Re-read them before applying; nothing was changed.',
      v_done, cardinality(c_sig), case when v_pol_done then 'changed' else 'as before' end,
      case when v_ph_done then 'changed' else 'as before' end,
      case when v_prof_done then 'changed' else 'as before' end, v_new_done, cardinality(c_new_sig); end if;
  -- The patches: each found exactly once, the result exactly the tested text.
  for i in 1 .. cardinality(c_fn) loop
    if (length(v_def[c_fn[i]]) - length(replace(v_def[c_fn[i]], c_anchor[i], ''))) / length(c_anchor[i]) <> 1 then
      raise exception '539: patch % does not find its text exactly once in public.%', i, c_sig[c_fn[i]]; end if;
    v_def[c_fn[i]] := replace(v_def[c_fn[i]], c_anchor[i], c_new[i]);
  end loop;
  for i in 1 .. cardinality(c_sig) loop
    if md5(v_def[i]) <> c_after[i] then
      raise exception '539: the patched text of public.% is not the tested one (md5 %)', c_sig[i], md5(v_def[i]); end if;
  end loop;
  for i in 1 .. cardinality(c_new_sig) loop
    if md5(c_new_def[i]) <> c_new_md5[i] then
      raise exception '539: the text of public.% is not the tested one (md5 %)', c_new_sig[i], md5(c_new_def[i]); end if;
  end loop;

  -- 2. Install: the new functions first (the patched ones call the guard)
  for i in 1 .. cardinality(c_new_sig) loop
    execute c_new_def[i];
    if c_new_acl[i] = 'postgres=X/postgres' then
      execute format('revoke all on function public.%s from public, anon, authenticated, service_role', c_new_sig[i]);
    else
      execute format('revoke all on function public.%s from public, anon', c_new_sig[i]);
      execute format('grant execute on function public.%s to authenticated, service_role', c_new_sig[i]);
    end if;
  end loop;
  for i in 1 .. cardinality(c_sig) loop
    execute v_def[i];
  end loop;
  execute format('alter policy %I on public.customers using (%s)', 'read customers', c_pol_src);
  execute format('alter policy %I on public.customer_phone_history using (%s)', 'read phone history', c_ph_src);
  revoke select on table public.profiles from authenticated, anon;
  execute format('grant select (%s) on table public.profiles to authenticated',
                 (select string_agg(quote_ident(x), ', ') from unnest(c_prof_read) x));
  -- 3. Checks after installing
  for i in 1 .. cardinality(c_sig) loop
    if md5(pg_get_functiondef(to_regprocedure('public.' || c_sig[i]))) <> c_after[i] then
      raise exception '539: public.% was installed with an md5 other than the tested one', c_sig[i]; end if;
    if (select coalesce(string_agg(x::text, ',' order by x::text), '')
          from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig[i])) is distinct from c_acl then
      raise exception '539: the grants of public.% changed', c_sig[i]; end if;
  end loop;
  if (select pg_get_expr(p.polqual, p.polrelid) from pg_policy p
       where p.polrelid = 'public.customers'::regclass and p.polname = 'read customers') is distinct from c_pol_after then
    raise exception '539: the read rule of public.customers is not the tested one (%)',
      (select pg_get_expr(p.polqual, p.polrelid) from pg_policy p where p.polrelid = 'public.customers'::regclass and p.polname = 'read customers'); end if;
  if (select pg_get_expr(p.polqual, p.polrelid) from pg_policy p
       where p.polrelid = 'public.customer_phone_history'::regclass and p.polname = 'read phone history') is distinct from c_ph_after then
    raise exception '539: the read rule of public.customer_phone_history is not the tested one'; end if;
  for i in 1 .. cardinality(c_new_sig) loop
    if md5(pg_get_functiondef(to_regprocedure('public.' || c_new_sig[i]))) <> c_new_md5[i] then
      raise exception '539: public.% was made with an md5 other than the tested one (md5 %)', c_new_sig[i],
        md5(pg_get_functiondef(to_regprocedure('public.' || c_new_sig[i]))); end if;
    if (select coalesce(string_agg(x::text, ',' order by x::text), '')
          from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_new_sig[i])) is distinct from c_new_acl[i]
       or has_function_privilege('anon', to_regprocedure('public.' || c_new_sig[i]), 'execute') then
      raise exception '539: the grants of public.% are not the tested ones', c_new_sig[i]; end if;
  end loop;
  if (select coalesce(string_agg(x::text, ',' order by x::text), '') from pg_class c, unnest(c.relacl) x
       where c.oid = 'public.profiles'::regclass) is distinct from c_prof_acl_after
     or has_table_privilege('authenticated', 'public.profiles', 'select')
     or has_table_privilege('anon', 'public.profiles', 'select')
     or has_any_column_privilege('anon', 'public.profiles', 'select')
     or not has_table_privilege('authenticated', 'public.profiles', 'update')
     or exists (select 1 from unnest(c_prof_hidden) x where has_column_privilege('authenticated', 'public.profiles', x, 'select'))
     or exists (select 1 from unnest(c_prof_read) x where not has_column_privilege('authenticated', 'public.profiles', x, 'select'))
     or not has_table_privilege('service_role', 'public.profiles', 'select') then
    raise exception '539: the grants on public.profiles are not the tested ones after installing'; end if;
  for i in 1 .. cardinality(c_relied) loop
    if md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i]))) <> c_relied_md5[i] then
      raise exception '539: public.% changed', c_relied[i]; end if;
  end loop;

  perform set_config('lock_timeout', v_lock, true);
  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $mig$;
