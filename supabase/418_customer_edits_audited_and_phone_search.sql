-- 418_customer_edits_audited_and_phone_search.sql
--
-- WHAT WAS WRONG (the audit of 9 Oct 2026: CUSTOMERS-9, -11, -15, -18; the
-- page parts of CUSTOMERS-13, -14 and -19 are in the front end)
--
--   1. Add and Edit on the Customers page wrote the customers table straight
--      from the browser (CUSTOMERS-9). The rules "insert customers" and
--      "update customers" let any active member of staff, Inventory Managers
--      too, write any of the 26 columns, and only a phone change left a trace
--      (customer_phone_history, with the reason "Customer phone updated").
--      Since 385 the Birthday discount reads customers.date_of_birth
--      (invoice_birthday_check), so a date of birth could be changed to give
--      the discount and changed back, and nothing would show it. Every save
--      also set is_referrer to true: on 9 Oct 2026, 122 customers had it, 108
--      of them with no friend and no affiliate record, so the export's "Is
--      Referrer" said nothing.
--   2. A phone typed with spaces or "+65 " found nobody (CUSTOMERS-11).
--      Phones are stored as +<digits>, and search_customers and
--      customer_survey_overview compared the text as typed. Staff then took
--      the customer for new and made a second record, which the October
--      referral promotion would count as a new friend.
--   3. delete_customer read the customer without a lock, and checked only
--      wallet credit, purchased therapy and unpaid invoices (CUSTOMERS-15). A
--      customer with a rental not returned, an open stock loan, an affiliate
--      record or login, commission not yet paid out, commission they owe back
--      (paid out, then taken back), or open legacy therapy could be deleted.
--      Latent: none of the 25 deleted customers had any, and on 9 Oct 2026 no
--      referrer owed anything back (after 414's settlement).
--   4. Opening balance and Adjust credit had no request id (CUSTOMERS-18). A
--      lost answer and a second press of Confirm posted twice. Both also let
--      the caller name another person as the approver. On 9 Oct 2026: 6
--      manual opening balances and 7 adjustments, no pair posted twice, and
--      no approver other than the person who entered it.
--
-- THE RULES
--
--   1. (the Owner, 9 Oct 2026, Q9 A) Any member of staff who edits customers
--      (rule 3) may fill in a date of birth that is missing. Changing or
--      clearing one that is already filled in needs an Owner or a Manager
--      (not the old Admin role), and a reason. Every change is recorded with
--      the old and the new date.
--   2. Every edit of a customer is recorded: one audit row, with the old and
--      the new value of each field that changed. A phone change needs a
--      reason, which also goes into the phone history.
--   3. (the Owner, 9 Oct 2026) Owners, Managers and Staff add and edit
--      customers: Add, Edit, Change phone, and Add customer on the Invoices
--      page. Inventory Managers do not; they look after stock and products
--      only (Q13 A). They still find, view and pick customers. The old Admin
--      role (none on production) keeps adding and editing, as before.
--   4. A referrer may be set on a customer who has none. Changing or removing
--      one stays with Correct Referrer (Owner/Manager, audited), as before.
--   5. (the Owner, 9 Oct 2026) Saving a customer never sets is_referrer.
--      "Is Referrer" in the Special Export means: has referred a customer who
--      is not deleted, or has an affiliate record that is not deleted.
--   6. A phone search matches the digits typed, whatever spaces, dashes or
--      "+65" are around them.
--   7. A customer is not deleted while anything is still open on them. That
--      includes (the Owner, 9 Oct 2026) commission they owe back as a
--      referrer: paid out, then taken back, and not yet recovered or settled
--      (414's settlements count). It is settled first: the Owner said "settle
--      or void first", which is Mark as settled on the Commissions page
--      (paid back, written off, or paid off outside the app).
--   8. An opening balance or adjustment sent twice with one request id is
--      recorded once. The approver is the person who enters it.
--   9. (the Owner, 9 Oct 2026) Add Customer has no Active box: a new customer
--      starts active, and can be switched off in Edit.
--
-- WHAT THIS DOES
--
--   * assert_customer_dob_change(p_customer_id, p_new_dob, p_reason) (new;
--     internal, the service role's alone, 339): rules 1 and 3. It only
--     checks; each caller saves the change and audits it. update_customer
--     calls it, and so will the survey's Edit details (B05's
--     update_survey_particulars_v2). A date that does not change passes for
--     any member of staff; an Inventory Manager changes none.
--   * update_customer(p_customer_id, p_changes, p_reason,
--     p_expected_updated_at) (new; staff): Edit on the Customers page. It
--     starts with require_active_staff('{owner,admin,manager,staff}') (406;
--     rule 3), locks the row, refuses a deleted customer and an edit made on
--     an older copy of the row, takes only the fields named in p_changes
--     (first and last name, phone, email, date of birth, gender, gender
--     other, occupation, notes, active, referrer), applies rules 1, 2 and 4,
--     never touches is_referrer, and writes one audit row 'customer_updated'
--     with the old and new values.
--   * create_customer_quick(...) (patched): Add on the Customers page uses it
--     too, with its request id. It starts with
--     require_active_staff('{owner,admin,manager,staff}') (406; rule 3)
--     instead of its own profile test, and no longer sets is_referrer.
--     Website orders still reach it: as the server, or as their channel's
--     acting profile (an Owner on production). Its history row is now
--     'customer_created' (it was 'customer_created_from_invoice'): the
--     Customers page, the Invoices page and website orders all add customers
--     through it, and it cannot tell which one called. Nothing reads the
--     action name.
--   * search_customers(...) and customer_survey_overview(...) (patched): rule
--     6. When the search is made only of phone characters (digits, spaces,
--     "+", "-", ".", brackets) and holds 4 digits or more, a phone (and in
--     search_customers an old phone) whose digits contain those digits
--     matches; "+65" with 8 digits also matches a number stored as the 8
--     digits alone. search_customers also finds a customer by their record
--     id (the phone review list names customers who have no customer number
--     by it), and its is_referrer is rule 5's.
--   * delete_customer(uuid,text,text) (patched): starts with
--     require_active_staff() (406) and is still Owner/Manager only. It takes
--     the payouts' lock (affiliate_payout_lock, as 414's Mark as settled
--     does, in the same order), locks the customer's row, and refuses (rule
--     7) a rental not returned or cancelled, an open stock loan, an affiliate
--     record not deleted or an affiliate login, commission still owed to
--     them as referrer (affiliate_referrer_balances().unpaid above zero),
--     commission they owe back (affiliate_referrer_balances().deduction above
--     zero), and legacy therapy active or waiting to start. Both commission
--     figures are netted as the Commissions page nets them (410), with 414's
--     settlements counted, so a row that only recovered a take-back, or a
--     deduction settled, does not stop a delete. Blocked commission (the
--     referrer was not an eligible affiliate) is never paid, so it does not
--     count. It never waits for the customer's row while it holds the
--     payouts' lock: if the row is busy, staff are asked to try again.
--   * change_customer_phone(uuid,text,text) (patched): starts with
--     require_active_staff('{owner,admin,manager,staff}') (406; rule 3).
--     The rest is as before (a login and a reason are still needed).
--   * customer_credit_entry_requests (new table): one row per request id of
--     an opening balance or adjustment, naming what it recorded. Row level
--     security on, no rules; no client role may touch it; the service role
--     may read it.
--   * add_legacy_credit and adjust_customer_credit (dropped and made again,
--     same argument types): the last argument is p_request_id where it was
--     p_approved_by. A request id seen before returns what was recorded
--     (rule 8); the approver is the caller. Both start with
--     require_active_staff() (406). One version of each, as 386/388/390 did.
--   * public.customers: INSERT and UPDATE revoked from anon and
--     authenticated, and the rules "insert customers" and "update customers"
--     dropped. Every database function that writes customers is SECURITY
--     DEFINER (13 on 9 Oct 2026), so they keep working.
--
-- NOT CHANGED
--
--   * Who may read customers ("read customers") and every other customer
--     function: Source (already refuses Inventory Managers), Correct
--     Referrer, restore, merge.
--   * update_survey_particulars still writes the date of birth without
--     rule 1 until B05's update_survey_particulars_v2 replaces it (419).
--   * invoice_birthday_check and the Birthday discount.
--   * Stored is_referrer values: none is changed (rule 5 is computed).
--   * create_customer_quick's argument list (so no overload is added). The 3
--     history rows already written as 'customer_created_from_invoice' keep
--     that name.
--   * No row of the app's tables changes. The phone and name tidy-up
--     (CUSTOMERS-17) is scripts/repairs/customer-phones-singapore.sql and
--     scripts/repairs/customer-names-whitespace.sql, run once by an Owner.
--   * Grants of every patched function are kept (CREATE OR REPLACE).
--
-- SAFETY
--
--   Apart from the lock timeout this is one DO block, so it is atomic. Each
--   changed function must be the production version read on 9 Oct 2026
--   (BEFORE) or already this migration's (AFTER), which is left alone, so a
--   re-run changes nothing. The new functions and the table must be missing
--   or already exactly this; no other function takes their names. The
--   functions and triggers relied on must be the versions read that day,
--   414's affiliate_month_balances included (so 414 must be in first). Every
--   anchor must match exactly once, and every text built is checked against
--   its AFTER md5 before anything is installed. The rules dropped must be the
--   ones read that day (or gone). The definitions are read and compared with
--   the search path set to public. After installing: the md5s, the grants
--   (patched functions keep theirs; the new staff function and the two credit
--   functions are authenticated's and the service role's;
--   assert_customer_dob_change is the service role's alone), the table, the
--   rules and the table grants are as tested. Then, inside a block that is
--   always undone, a made-up member of staff fills in a missing date of birth
--   and is refused changing it and writing the table directly, a phone typed
--   with a space is found, a made-up Inventory Manager is refused adding,
--   editing and changing a phone, a made-up Owner changes the date with a
--   reason and the audit row holds the old and new date, and an opening
--   balance sent twice with one request id is recorded once. Nothing is
--   printed and no row remains.
--
-- BEFORE (production, 9 Oct 2026; md5 of pg_get_functiondef, search_path public):
--   changed
--   create_customer_quick(text,text,text,text,date,text,text,text,text,uuid,uuid)
--                                                              851b2d078f24668f17f2dd2f8b1bc1b9
--   search_customers(text,text,integer,integer,text,date,date) 37cfdf902b98e800446211e9a4fdbabb
--   customer_survey_overview(text,text,integer,integer)        900cfd200ddbdcb69ce87d3b6cdbc3e5
--   delete_customer(uuid,text,text)                            921fc8b248ed4bc72344440ae7368a71
--   add_legacy_credit(uuid,text,numeric,date,uuid,text,text,date,uuid)
--                                                              21310537240ba411bf3f82e8d982312e
--   adjust_customer_credit(uuid,text,text,numeric,text,text,date,text,uuid,uuid)
--                                                              aa8253586ad1769b4a075d1adbedaf63
--   change_customer_phone(uuid,text,text)                      d8a066be954bd7c7db9049139330d8b0
--   new: assert_customer_dob_change(uuid,date,text), update_customer(uuid,jsonb,text,timestamptz) (missing)
--   relied on, not changed
--   require_active_staff(text[])                               877b3aa74cea559881979bb161c450e2
--   normalize_customer_phone(text)                             b2bfac910e0c9eff402ba44e19750bee
--   write_audit_ex(text,uuid,text,jsonb,jsonb,text,text,uuid,text,text)
--                                                              c705c733e213a27f0dc32d54322cc855
--   can_manage_customer_credit()                               a576249272a4c7fb68965d0f62649ed4
--   is_owner_or_manager()                                      125dec10ce33b84ff5fb40a9bd455235
--   grant_customer_credit(uuid,text,numeric,text,uuid,uuid,date,text,text,text,date,uuid,jsonb)
--                                                              ac0de5530624ee533aacf93aec389910
--   ensure_customer_wallet(uuid)                               8ef18daebbbe3c12f2024290ea8416e8
--   trg_sync_person_name()                                     bdfc01a20c6d82672a24c694a0ea917b
--   audit_customer_phone_change()                              414b5857bccb5b06d7ef3278dc754617
--   enforce_referral_ownership()                               437c1677a8a319eb573f3e5132b4fd32
--   normalize_current_customer_phone()                         d05e8caea5d619372206a3191bc9e782
--   tg_customers_referral_date()                               5ea2010a7b31efd4db32474723f814f6
--   set_updated_at()                                           ffc2b9b80f7c977fb37f97b9c4d28802
--   affiliate_referrer_balances()                              54ef098ba8f9e3d81bb45906c4607ab6
--   affiliate_month_balances()                                 84c0741e983c8f483d677353c732d891  (414's AFTER)
--   affiliate_payout_lock()                                    c410a35592ecae0ec9af516e5595f272
--   public function fingerprint (414, 421, 428 and 415 in)     566e76f702c89c9846968e6fdd89cc45
--   Every BEFORE md5 above was read again from production on 10 Oct 2026,
--   after 414, 421, 428 and 415 were applied, and matched. 415 (events and
--   website orders) changes none of them.
-- AFTER (for later guards):
--   assert_customer_dob_change(uuid,date,text)                 3d9fc369da08a6baf623f842999f0156
--   update_customer(uuid,jsonb,text,timestamptz)               6511100316418394409d8baf1d2b52e0
--   create_customer_quick(...)                                 9ff9031d3b40029a19c729a512e99798
--   search_customers(text,text,integer,integer,text,date,date) a7403700638459c6567a039ddab398f9
--   customer_survey_overview(text,text,integer,integer)        35ca42db5c30258f0c4d0026334fed2c
--   delete_customer(uuid,text,text)                            5b407735574fc3cacd8067c4dc8213f4
--   add_legacy_credit(uuid,text,numeric,date,uuid,text,text,date,uuid)
--                                                              0351aa4ce473ce1309be1cfdff6ad613
--   adjust_customer_credit(uuid,text,text,numeric,text,text,date,text,uuid,uuid)
--                                                              34724253ceddb93c99279a3cb27ed445
--   change_customer_phone(uuid,text,text)                      ee676507d0ded28e1023bdee3b1f5488
--   public function fingerprint (from 566e76f7…)               30132638a6e544de886be51917a41a38
--
-- DEPLOY ORDER: after 414 (live; 418 refuses without it). This, then the
-- front end at once: the Customers page, and the Add a customer window the
-- Invoices page uses (it tells an Inventory Manager to pick a customer). The
-- page live now writes the table directly, so between the two its Add and
-- Edit fail ("permission denied for table customers"); its Opening balance
-- and Adjust keep working (they never sent p_approved_by, and p_request_id
-- is optional). The new page against a database without this fails Edit (no
-- update_customer) and both credit windows (no p_request_id), so this goes
-- first. B05's 419 goes after this (it calls assert_customer_dob_change,
-- whose AFTER md5 is above). The tidy-up scripts run after this, by an
-- Owner.
--
-- Test: scripts/customers/tests/customer-edits.sql (rules 1 and 3, the
-- audit, the stale edit, the phone reason, the referrer, the direct writes,
-- rule 5),
-- scripts/customers/tests/credit-request-ids.sql (rule 8),
-- scripts/customer-merge/tests/delete-refusals.sql (rule 7: commission owed
-- to them and owed back, netted, with 414's settlements; blocked commission),
-- scripts/referrals/tests/customer-paging.sql (rule 6, and the paging),
-- scripts/quick-customer/tests/create-and-match.sql,
-- scripts/permissions/tests/function-grants.sql and staff-only-functions.sql;
-- the page: scripts/customers/tests/customers-page.test.mjs and
-- phone-search.test.mjs.

set lock_timeout = '5s';

do $mig$
declare
  -- ── New: the date-of-birth rule (internal) ────────────────────────────────
  c_dob_def constant text := $def$CREATE OR REPLACE FUNCTION public.assert_customer_dob_change(p_customer_id uuid, p_new_dob date, p_reason text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_role public.user_role; v_old date;
begin
  -- 418: the date-of-birth rule (the Owner, 9 Oct 2026). The Birthday
  -- discount reads the date of birth, so:
  --   * any member of staff may fill in a date of birth that is missing;
  --   * changing or clearing one that is already filled in needs an Owner or
  --     a Manager, and a reason.
  --   * an Inventory Manager changes no customer's date of birth: customers
  --     are for Owners, Managers and Staff (the Owner, 9 Oct 2026).
  -- This only checks. It changes nothing and writes nothing: each caller
  -- saves the change and records the old and the new date in its own audit
  -- row (update_customer for the Customers page, and the survey's Edit
  -- details). The server (no login) passes the role test, as in
  -- require_active_staff, but still needs a reason.
  v_role := public.require_active_staff();
  select c.date_of_birth into v_old from public.customers c where c.id = p_customer_id for update;
  if not found then
    raise exception 'That customer does not exist';
  end if;
  if p_new_dob is not distinct from v_old then
    return;
  end if;
  if v_role is not null and v_role::text not in ('owner', 'admin', 'manager', 'staff') then
    raise exception 'Only Owners, Managers and Staff can change a customer''s details.' using errcode = '42501';
  end if;
  if v_old is null then
    return;
  end if;
  if v_role is not null and v_role::text not in ('owner', 'manager') then
    raise exception 'Only an Owner or Manager can change a date of birth that is already filled in.'
      using errcode = '42501';
  end if;
  if nullif(btrim(coalesce(p_reason, '')), '') is null then
    raise exception 'A reason is required to change a date of birth that is already filled in.';
  end if;
end
$function$
$def$;
  -- ── New: Edit on the Customers page ───────────────────────────────────────
  c_update_def constant text := $def$CREATE OR REPLACE FUNCTION public.update_customer(p_customer_id uuid, p_changes jsonb, p_reason text DEFAULT NULL::text, p_expected_updated_at timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  c_fields constant text[] := array['first_name', 'last_name', 'phone', 'email', 'date_of_birth', 'gender',
                                    'gender_other', 'occupation', 'notes', 'is_active', 'referred_by'];
  v_old public.customers%rowtype;
  v_new public.customers%rowtype;
  v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
  v_key text;
  v_text text;
  v_changed text[] := '{}';
  v_before jsonb := '{}'::jsonb;
  v_after jsonb := '{}'::jsonb;
begin
  perform public.require_active_staff('{owner,admin,manager,staff}');  -- 406: active staff; not Inventory Managers
  -- 418: Edit on the Customers page (CUSTOMERS-9). Staff no longer write the
  -- customers table; an edit is saved here, and only here.
  --   * Owners, Managers and Staff (and the old Admin role) edit customers;
  --     Inventory Managers look after stock and products only (the Owner,
  --     9 Oct 2026).
  --   * p_changes holds only the fields being changed. A field not listed
  --     here (is_referrer, the source, deleted, ...) is refused.
  --   * The row is locked. If it changed after the page read it
  --     (p_expected_updated_at), nothing is saved.
  --   * A date of birth follows assert_customer_dob_change (the Owner's rule).
  --   * A phone change needs a reason; it goes into the phone history.
  --   * A referrer may be set when there is none. Changing or removing one is
  --     Correct Referrer's (reassign_customer_referrer, Owner/Manager).
  --   * is_referrer is never touched.
  --   * One audit row, customer_updated, holds the old and the new value of
  --     every field that changed. An edit that changes nothing writes nothing.
  if p_customer_id is null then
    raise exception 'A customer is required';
  end if;
  if jsonb_typeof(p_changes) is distinct from 'object' then
    raise exception 'The changes must be a list of fields and their new values';
  end if;
  select k into v_key from jsonb_object_keys(p_changes) k where not (k = any (c_fields)) order by k limit 1;
  if v_key is not null then
    raise exception 'The field "%" cannot be changed here', v_key;
  end if;

  select * into v_old from public.customers c where c.id = p_customer_id for update;
  if not found then
    raise exception 'That customer does not exist';
  end if;
  if v_old.deleted_at is not null then
    raise exception 'That customer has been deleted. Restore them before changing their details.';
  end if;
  if p_expected_updated_at is not null and v_old.updated_at is distinct from p_expected_updated_at then
    raise exception 'STALE_CUSTOMER: Someone else changed this customer after you opened it. Close this window and open it again.';
  end if;

  v_new := v_old;
  if p_changes ? 'first_name' then
    v_new.first_name := nullif(btrim(coalesce(p_changes->>'first_name', '')), '');
    if v_new.first_name is null then
      raise exception 'A first name is required';
    end if;
  end if;
  if p_changes ? 'last_name' then
    v_new.last_name := nullif(btrim(coalesce(p_changes->>'last_name', '')), '');
  end if;
  if p_changes ? 'phone' then
    v_text := nullif(btrim(coalesce(p_changes->>'phone', '')), '');
    if v_text is null then
      raise exception 'Phone number is required. Up to 3 non-deleted customers may share a number.';
    end if;
    -- As it will be stored: the phone trigger keeps the normalised number.
    v_new.phone := coalesce(public.normalize_customer_phone(v_text), v_text);
  end if;
  if p_changes ? 'email' then
    v_new.email := nullif(btrim(coalesce(p_changes->>'email', '')), '');
  end if;
  if p_changes ? 'date_of_birth' then
    begin
      v_new.date_of_birth := nullif(btrim(coalesce(p_changes->>'date_of_birth', '')), '')::date;
    exception when invalid_datetime_format or datetime_field_overflow then
      raise exception 'The date of birth is not a valid date';
    end;
  end if;
  if p_changes ? 'gender' then
    begin
      v_new.gender := nullif(btrim(coalesce(p_changes->>'gender', '')), '')::public.customer_gender;
    exception when invalid_text_representation then
      raise exception 'Gender must be male, female or other';
    end;
  end if;
  if p_changes ? 'gender_other' then
    v_new.gender_other := nullif(btrim(coalesce(p_changes->>'gender_other', '')), '');
  end if;
  if (p_changes ? 'gender' or p_changes ? 'gender_other') and v_new.gender is distinct from 'other' then
    v_new.gender_other := null;  -- kept only beside Other, as the page does
  end if;
  if p_changes ? 'occupation' then
    v_new.occupation := nullif(btrim(coalesce(p_changes->>'occupation', '')), '');
  end if;
  if p_changes ? 'notes' then
    v_new.notes := nullif(btrim(coalesce(p_changes->>'notes', '')), '');
  end if;
  if p_changes ? 'is_active' then
    if jsonb_typeof(p_changes->'is_active') is distinct from 'boolean' then
      raise exception 'Active must be true or false';
    end if;
    v_new.is_active := (p_changes->>'is_active')::boolean;
  end if;
  if p_changes ? 'referred_by' then
    begin
      v_new.referred_by := nullif(btrim(coalesce(p_changes->>'referred_by', '')), '')::uuid;
    exception when invalid_text_representation then
      raise exception 'The referrer is not a valid customer id';
    end;
  end if;
  if v_new.referred_by is distinct from v_old.referred_by then
    if v_old.referred_by is not null then
      raise exception 'This customer already has a referrer. Use Correct Referrer (Owner/Manager) to change it.';
    end if;
    if not exists (select 1 from public.customers r where r.id = v_new.referred_by and r.deleted_at is null) then
      raise exception 'That referrer is not on the customer list';
    end if;
  end if;

  foreach v_key in array c_fields loop
    if (to_jsonb(v_new) -> v_key) is distinct from (to_jsonb(v_old) -> v_key) then
      v_changed := v_changed || v_key;
    end if;
  end loop;
  if cardinality(v_changed) = 0 then
    return jsonb_build_object('customer_id', p_customer_id, 'changed', '[]'::jsonb,
                              'full_name', v_old.full_name, 'updated_at', v_old.updated_at);
  end if;

  if 'date_of_birth' = any (v_changed) then
    perform public.assert_customer_dob_change(p_customer_id, v_new.date_of_birth, v_reason);
  end if;
  if 'phone' = any (v_changed) then
    if v_reason is null then
      raise exception 'A reason is required to change a customer''s phone number';
    end if;
    perform set_config('energia.phone_change_reason', v_reason, true);
  end if;

  update public.customers c
     set first_name = v_new.first_name, last_name = v_new.last_name, phone = v_new.phone,
         email = v_new.email, date_of_birth = v_new.date_of_birth, gender = v_new.gender,
         gender_other = v_new.gender_other, occupation = v_new.occupation, notes = v_new.notes,
         is_active = v_new.is_active, referred_by = v_new.referred_by
   where c.id = p_customer_id
  returning * into v_new;

  -- The values as stored (the phone normalised; the whole name rebuilt).
  foreach v_key in array v_changed loop
    v_before := v_before || jsonb_build_object(v_key, to_jsonb(v_old) -> v_key);
    v_after := v_after || jsonb_build_object(v_key, to_jsonb(v_new) -> v_key);
  end loop;
  if v_new.full_name is distinct from v_old.full_name then
    v_before := v_before || jsonb_build_object('full_name', v_old.full_name);
    v_after := v_after || jsonb_build_object('full_name', v_new.full_name);
  end if;
  perform public.write_audit_ex('customers', p_customer_id, 'customer_updated', v_before, v_after,
                                'customers', v_reason, null::uuid);
  return jsonb_build_object('customer_id', p_customer_id, 'changed', to_jsonb(v_changed),
                            'full_name', v_new.full_name, 'updated_at', v_new.updated_at);
end
$function$
$def$;
  -- ── Made again with a request id ──────────────────────────────────────────
  c_legacy_def constant text := $def$CREATE OR REPLACE FUNCTION public.add_legacy_credit(p_customer_id uuid, p_category text, p_amount numeric, p_original_purchase_date date, p_store_id uuid, p_reference_no text, p_note text, p_effective_date date DEFAULT NULL::date, p_request_id uuid DEFAULT NULL::uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_lot uuid;
  v_seen public.customer_credit_entry_requests%rowtype;
  v_ref text := nullif(trim(coalesce(p_reference_no,'')),'');
begin
  perform public.require_active_staff();  -- 406: active staff only
  if not public.can_manage_customer_credit() then
    raise exception 'Only an Owner or Manager can enter old-client balances';
  end if;
  -- 418: a retry, or a second press of Confirm, returns the balance the first
  -- call recorded (CUSTOMERS-18). The page sends one request id per window.
  if p_request_id is not null then
    perform pg_advisory_xact_lock(hashtextextended('customer-credit-entry:' || p_request_id::text, 0));
    select * into v_seen from public.customer_credit_entry_requests r where r.request_id = p_request_id;
    if found then
      if v_seen.entry_kind <> 'opening_balance' or v_seen.customer_id <> p_customer_id then
        raise exception 'That request was already used for another entry. Close the window and open it again.';
      end if;
      return v_seen.entry_id;
    end if;
  end if;
  if p_category not in ('paid','bonus','legacy') then
    raise exception 'An opening balance may only be Paid, Bonus or Legacy credit';
  end if;
  if p_customer_id is null then raise exception 'A customer is required'; end if;
  if coalesce(p_amount,0) <= 0 then raise exception 'Amount must be greater than zero'; end if;
  if p_original_purchase_date is null then raise exception 'The original purchase date is required'; end if;
  if p_store_id is null then raise exception 'The store is required'; end if;
  if coalesce(trim(p_note),'') = '' then raise exception 'A supporting note is required'; end if;

  -- A reference is optional, but must be unique when given.
  if v_ref is not null and exists (
        select 1 from public.customer_credit_lots
         where source_type = 'manual_legacy' and reference_no = v_ref) then
    raise exception 'Reference number "%" has already been used for a manual legacy entry', v_ref;
  end if;

  -- 418: the approver is the person entering it. The caller can no longer
  -- name someone else.
  v_lot := public.grant_customer_credit(
    p_customer_id, p_category, p_amount, 'manual_legacy', null, p_store_id,
    coalesce(p_effective_date, p_original_purchase_date), v_ref,
    'Old-client opening balance', p_note, p_original_purchase_date, auth.uid());
  if p_request_id is not null then
    insert into public.customer_credit_entry_requests (request_id, entry_kind, customer_id, entry_id, created_by)
    values (p_request_id, 'opening_balance', p_customer_id, v_lot, auth.uid());
  end if;
  return v_lot;
end
$function$
$def$;
  c_adjust_def constant text := $def$CREATE OR REPLACE FUNCTION public.adjust_customer_credit(p_customer_id uuid, p_category text, p_direction text, p_amount numeric, p_reason text, p_reference_no text, p_effective_date date DEFAULT NULL::date, p_note text DEFAULT NULL::text, p_store_id uuid DEFAULT NULL::uuid, p_request_id uuid DEFAULT NULL::uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_wallet uuid; v_lot uuid; v_entry uuid; v_adj uuid; v_eff date;
  v_left numeric; v_take numeric; v_l record; v_approver uuid;
  v_seen public.customer_credit_entry_requests%rowtype;
  v_ref text := nullif(trim(coalesce(p_reference_no,'')),'');
begin
  perform public.require_active_staff();  -- 406: active staff only
  if not public.can_manage_customer_credit() then
    raise exception 'Only an Owner or Manager can adjust customer credit';
  end if;
  -- 418: a retry, or a second press of Confirm, returns the adjustment the
  -- first call recorded (CUSTOMERS-18). The page sends one request id per window.
  if p_request_id is not null then
    perform pg_advisory_xact_lock(hashtextextended('customer-credit-entry:' || p_request_id::text, 0));
    select * into v_seen from public.customer_credit_entry_requests r where r.request_id = p_request_id;
    if found then
      if v_seen.entry_kind <> 'adjustment' or v_seen.customer_id <> p_customer_id then
        raise exception 'That request was already used for another entry. Close the window and open it again.';
      end if;
      return v_seen.entry_id;
    end if;
  end if;
  if p_direction not in ('increase','decrease') then raise exception 'Direction must be increase or decrease'; end if;
  if coalesce(p_amount,0) <= 0 then raise exception 'Amount must be greater than zero'; end if;
  if coalesce(trim(p_reason),'') = '' then raise exception 'A reason is required'; end if;

  v_eff := coalesce(p_effective_date, public.sg_today());
  -- 418: the approver is the person entering it. The caller can no longer
  -- name someone else.
  v_approver := auth.uid();
  v_wallet := public.ensure_customer_wallet(p_customer_id);

  if v_ref is not null and exists (
        select 1 from public.customer_credit_adjustments where reference_no = v_ref) then
    raise exception 'Reference number "%" has already been used for an adjustment', v_ref;
  end if;

  if p_direction = 'increase' then
    v_lot := public.grant_customer_credit(p_customer_id, p_category, p_amount,
      'manual_adjustment', null, p_store_id, v_eff, v_ref, p_reason, p_note, null, v_approver);
    select id into v_entry from public.customer_credit_ledger
     where lot_id = v_lot and entry_type = 'grant' limit 1;
  else
    select coalesce(sum(remaining_amount),0) into v_left
      from public.customer_credit_lots
     where customer_id = p_customer_id and category = p_category and status = 'active';
    if v_left < round(p_amount,2) then
      raise exception 'Cannot decrease % credit by % — only % is available', p_category, p_amount, v_left;
    end if;

    insert into public.customer_credit_ledger (
      wallet_id, customer_id, entry_type, category, amount, source_type,
      store_id, effective_date, reference_no, reason, note, created_by, approved_by)
    values (v_wallet, p_customer_id, 'adjust_decrease', p_category, round(p_amount,2),
      'manual_adjustment', p_store_id, v_eff, v_ref, p_reason, p_note, auth.uid(), v_approver)
    returning id into v_entry;

    v_take := round(p_amount,2);
    for v_l in
      select id, remaining_amount from public.customer_credit_lots
       where customer_id = p_customer_id and category = p_category
         and status = 'active' and remaining_amount > 0
       order by effective_date, created_at for update
    loop
      exit when v_take <= 0;
      if v_l.remaining_amount >= v_take then
        update public.customer_credit_lots
           set remaining_amount = remaining_amount - v_take, updated_at = now() where id = v_l.id;
        insert into public.customer_credit_allocations (ledger_entry_id, lot_id, customer_id, amount)
        values (v_entry, v_l.id, p_customer_id, v_take);
        v_take := 0;
      else
        update public.customer_credit_lots
           set remaining_amount = 0, updated_at = now() where id = v_l.id;
        insert into public.customer_credit_allocations (ledger_entry_id, lot_id, customer_id, amount)
        values (v_entry, v_l.id, p_customer_id, v_l.remaining_amount);
        v_take := v_take - v_l.remaining_amount;
      end if;
    end loop;
    -- 353: the balance was checked before the lots were locked. If a sale spent
    -- some of it in between, the ledger entry above already records the full
    -- amount, so stop rather than leave the ledger and the lots disagreeing.
    if v_take > 0 then
      raise exception 'The % credit balance changed while it was being adjusted; nothing was changed. Please try again.', p_category;
    end if;
  end if;

  insert into public.customer_credit_adjustments (
    customer_id, category, direction, amount, reason, note, reference_no,
    effective_date, ledger_entry_id, lot_id, created_by, approved_by)
  values (p_customer_id, p_category, p_direction, round(p_amount,2), p_reason, p_note,
    v_ref, v_eff, v_entry, v_lot, auth.uid(), v_approver)
  returning id into v_adj;

  perform public.write_audit_ex('customer_credit_adjustments', v_adj, 'credit_adjusted', null,
    jsonb_build_object('customer', p_customer_id, 'category', p_category,
      'direction', p_direction, 'amount', p_amount, 'reference', v_ref),
    'credit', p_reason, p_store_id);
  if p_request_id is not null then
    insert into public.customer_credit_entry_requests (request_id, entry_kind, customer_id, entry_id, created_by)
    values (p_request_id, 'adjustment', p_customer_id, v_adj, auth.uid());
  end if;
  return v_adj;
end
$function$
$def$;

  -- ── create_customer_quick: the 406 check, and no is_referrer ──────────────
  c_quick_check_a constant text := $a$  if not exists (select 1 from public.profiles
                  where id = auth.uid() and is_active and deleted_at is null) then
    raise exception 'You do not have permission to add customers' using errcode='42501'; end if;
$a$;
  c_quick_check_r constant text := $a$  -- 418: active staff, as 406. Owners, Managers and Staff (and the old Admin
  -- role) add customers; Inventory Managers do not (the Owner, 9 Oct 2026).
  perform public.require_active_staff('{owner,admin,manager,staff}');
$a$;
  c_quick_ref_a constant text := $a$     true, p_referred_by, true)
$a$;
  c_quick_ref_r constant text := $a$     -- 418: a new customer is not marked a referrer. The Customers page
     -- set it on every save, so the flag said nothing.
     true, p_referred_by, false)
$a$;
  c_quick_audit_a constant text := $a$  perform public.write_audit('customers', v_id, 'customer_created_from_invoice', null,
$a$;
  c_quick_audit_r constant text := $a$  -- 418: the Customers page, the Invoices page and website orders all add
  -- customers here, so the history says only that the customer was added.
  perform public.write_audit('customers', v_id, 'customer_created', null,
$a$;

  -- ── search_customers: phone digits, and what "Is Referrer" means ──────────
  c_search_q_a constant text := $a$  with q as (
    select nullif(trim(coalesce(p_query,'')),'') as term,
           public.current_user_role() is not null as staff
  ),
$a$;
  c_search_q_r constant text := $a$  with q as (
    select nullif(trim(coalesce(p_query,'')),'') as term,
           public.current_user_role() is not null as staff,
           -- 418: a phone typed with spaces, dashes or "+65" (CUSTOMERS-11).
           -- Phones are stored as +<digits>, so a search made only of phone
           -- characters, with 4 digits or more, also matches on its digits.
           -- "+65" and 8 digits also matches the 8 digits alone (a number
           -- stored without its country code).
           d.digits,
           case when d.digits ~ '^65[0-9]{8}$' then substr(d.digits, 3) end as national,
           -- 418: a customer's record id finds them (the phone review list
           -- names customers with no customer number by their id).
           case when trim(coalesce(p_query, '')) ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
                then trim(p_query)::uuid end as term_id
      from (select case when trim(coalesce(p_query, '')) ~ '^[0-9+().[:space:]-]+$'
                         and length(regexp_replace(p_query, '[^0-9]', '', 'g')) >= 4
                        then regexp_replace(p_query, '[^0-9]', '', 'g') end as digits) d
  ),
$a$;
  c_search_match_a constant text := $a$            or c.phone     ilike '%' || q.term || '%'
            or c.email     ilike '%' || q.term || '%'
            or c.notes     ilike '%' || q.term || '%'
            or exists (select 1 from public.customer_phone_history h
                        where h.customer_id = c.id
                          and h.phone ilike '%' || q.term || '%'))
$a$;
  c_search_match_r constant text := $a$            or c.id = q.term_id
            or c.phone     ilike '%' || q.term || '%'
            or c.phone     like '%' || q.digits || '%'
            or c.phone     like '%' || q.national || '%'
            or c.email     ilike '%' || q.term || '%'
            or c.notes     ilike '%' || q.term || '%'
            or exists (select 1 from public.customer_phone_history h
                        where h.customer_id = c.id
                          and (h.phone ilike '%' || q.term || '%'
                               or regexp_replace(h.phone, '[^0-9]', '', 'g') like '%' || q.digits || '%'
                               or regexp_replace(h.phone, '[^0-9]', '', 'g') like '%' || q.national || '%')))
$a$;
  c_search_ref_a constant text := $a$         m.is_active, m.created_at, m.referred_by, m.is_referrer,
$a$;
  c_search_ref_r constant text := $a$         m.is_active, m.created_at, m.referred_by,
         -- 418: "Is Referrer": has referred someone (a customer not deleted)
         -- or is an affiliate. The stored flag was set on every save from the
         -- Customers page, so it said nothing.
         (exists (select 1 from public.customers d where d.referred_by = m.id and d.deleted_at is null)
          or exists (select 1 from public.customer_affiliates a
                      where a.customer_id = m.id and a.deleted_at is null)),
$a$;

  -- ── customer_survey_overview: phone digits ────────────────────────────────
  c_survey_a constant text := $a$            or c.phone     ilike '%' || trim(p_query) || '%'
$a$;
  c_survey_r constant text := $a$            or c.phone     ilike '%' || trim(p_query) || '%'
            -- 418: a phone typed with spaces, dashes or "+65" matches on its
            -- digits, as in search_customers (CUSTOMERS-11).
            or (trim(coalesce(p_query, '')) ~ '^[0-9+().[:space:]-]+$'
                and length(regexp_replace(p_query, '[^0-9]', '', 'g')) >= 4
                and (c.phone like '%' || regexp_replace(p_query, '[^0-9]', '', 'g') || '%'
                     or (regexp_replace(p_query, '[^0-9]', '', 'g') ~ '^65[0-9]{8}$'
                         and c.phone like '%' || substr(regexp_replace(p_query, '[^0-9]', '', 'g'), 3) || '%')))
$a$;

  -- ── delete_customer: the 406 check, a lock, and what is still open ────────
  c_delete_decl_a constant text := $a$  v_unpaid integer := 0;
begin
$a$;
  c_delete_decl_r constant text := $a$  v_unpaid integer := 0;
  v_open integer := 0;
  v_owes numeric;
  v_due numeric;
begin
$a$;
  c_delete_check_a constant text := $a$  if not public.is_owner_or_manager() then
$a$;
  c_delete_check_r constant text := $a$  perform public.require_active_staff();  -- 418: active staff only, as 406
  if not public.is_owner_or_manager() then
$a$;
  c_delete_lock_a constant text := $a$  select * into v_c from public.customers where id = p_customer_id;
$a$;
  c_delete_lock_r constant text := $a$  -- 418: locked. Anything that would point at this customer (a sale, a
  -- rental, credit) waits until this has finished. The payouts' lock is
  -- taken first, in the order 414's Mark as settled takes them, so what the
  -- customer owes back as a referrer cannot move while this checks it.
  -- It never waits for the row while it holds the payouts' lock: a sale for
  -- this customer may hold the row and be waiting for that lock, and the two
  -- would wait for each other. If the row is busy, staff try again.
  perform public.affiliate_payout_lock();
  begin
    select * into v_c from public.customers where id = p_customer_id for update nowait;
  exception when lock_not_available then
    raise exception 'This customer is being changed in another action right now. Try again in a moment.';
  end;
$a$;
  c_delete_open_a constant text := $a$  update public.customers
     set deleted_at = now(),
$a$;
  c_delete_open_r constant text := $a$  -- 418: nor while anything else is still open on them (CUSTOMERS-15).
  select count(*) into v_open from public.rentals r
   where r.customer_id = p_customer_id and r.returned_at is null and r.cancelled_at is null;
  if v_open > 0 then
    raise exception 'This customer has % rental(s) not yet returned or cancelled. Settle them first.', v_open;
  end if;
  select count(*) into v_open from public.stock_loans l
   where l.customer_id = p_customer_id and l.status = 'open';
  if v_open > 0 then
    raise exception 'This customer has % stock loan(s) still open. Close them first.', v_open;
  end if;
  if exists (select 1 from public.customer_affiliates a
              where a.customer_id = p_customer_id and a.deleted_at is null)
     or exists (select 1 from public.affiliate_accounts aa
                 where aa.customer_id = p_customer_id and aa.status = 'claimed') then
    raise exception 'This customer is an affiliate (or has an affiliate login), so they cannot be deleted.';
  end if;
  -- Commission still owed to them, and commission they owe back, netted as
  -- the Commissions page nets it (410), with 414's settlements counted. So a
  -- row that only went to recover a take-back does not count, though it
  -- never goes in a payout. Blocked commission (the referrer was not an
  -- eligible affiliate) is never paid, so it does not count either.
  select r.unpaid, r.deduction into v_due, v_owes from public.affiliate_referrer_balances() r where r.referrer = p_customer_id;
  if coalesce(v_due, 0) > 0 then
    raise exception 'This customer is still owed S$% commission as a referrer. Record the payout on the Commissions page first.',
      to_char(v_due, 'FM999999990.00');
  end if;
  -- Nor while they owe commission back: paid out, then taken back, and not
  -- yet recovered or settled (the Owner, 9 Oct 2026).
  if coalesce(v_owes, 0) > 0 then
    raise exception 'This customer still owes S$% back from commission that was paid out and then taken back. Settle it, or write it off, with Mark as settled on the Commissions page first.',
      to_char(v_owes, 'FM999999990.00');
  end if;
  select count(*) into v_open from public.therapy_entitlements t
   where t.customer_id = p_customer_id and t.status in ('active', 'pending_activation');
  if v_open > 0 then
    raise exception 'This customer has % legacy therapy entitlement(s) still open. Settle them first.', v_open;
  end if;

  update public.customers
     set deleted_at = now(),
$a$;

  -- ── change_customer_phone: not Inventory Managers ─────────────────────────
  c_phone_a constant text := $a$  if auth.uid() is null or public.current_user_role() is null then raise exception 'Not authorized'; end if;
$a$;
  c_phone_r constant text := $a$  -- 418: active staff, as 406. Owners, Managers and Staff (and the old Admin
  -- role) change a customer's phone; Inventory Managers do not (the Owner,
  -- 9 Oct 2026). The server still needs a login, as before.
  perform public.require_active_staff('{owner,admin,manager,staff}');
  if auth.uid() is null or public.current_user_role() is null then raise exception 'Not authorized'; end if;
$a$;

  -- ── md5s ──────────────────────────────────────────────────────────────────
  c_dob_after    constant text := '3d9fc369da08a6baf623f842999f0156';
  c_update_after constant text := '6511100316418394409d8baf1d2b52e0';
  c_quick_after  constant text := '9ff9031d3b40029a19c729a512e99798';
  c_search_after constant text := 'a7403700638459c6567a039ddab398f9';
  c_survey_after constant text := '35ca42db5c30258f0c4d0026334fed2c';
  c_delete_after constant text := '5b407735574fc3cacd8067c4dc8213f4';
  c_legacy_after constant text := '0351aa4ce473ce1309be1cfdff6ad613';
  c_adjust_after constant text := '34724253ceddb93c99279a3cb27ed445';
  c_phone_after  constant text := 'ee676507d0ded28e1023bdee3b1f5488';
  c_legacy_before constant text := '21310537240ba411bf3f82e8d982312e';
  c_adjust_before constant text := 'aa8253586ad1769b4a075d1adbedaf63';
  c_dob_fn    constant text := 'assert_customer_dob_change(uuid,date,text)';
  c_update_fn constant text := 'update_customer(uuid,jsonb,text,timestamp with time zone)';
  c_quick_fn  constant text := 'create_customer_quick(text,text,text,text,date,text,text,text,text,uuid,uuid)';
  c_search_fn constant text := 'search_customers(text,text,integer,integer,text,date,date)';
  c_survey_fn constant text := 'customer_survey_overview(text,text,integer,integer)';
  c_delete_fn constant text := 'delete_customer(uuid,text,text)';
  c_legacy_fn constant text := 'add_legacy_credit(uuid,text,numeric,date,uuid,text,text,date,uuid)';
  c_adjust_fn constant text := 'adjust_customer_credit(uuid,text,text,numeric,text,text,date,text,uuid,uuid)';
  c_phone_fn  constant text := 'change_customer_phone(uuid,text,text)';

  -- customer_credit_entry_requests as this makes it: columns, then constraints.
  c_req_cols constant text := 'request_id uuid not null|entry_kind text not null|customer_id uuid not null|entry_id uuid not null|created_by uuid|created_at timestamp with time zone not null default now()';
  c_req_cons constant text := 'CHECK ((entry_kind = ANY (ARRAY[''opening_balance''::text, ''adjustment''::text])))|FOREIGN KEY (created_by) REFERENCES profiles(id)|PRIMARY KEY (request_id)';
  -- The customers columns update_customer reads and writes, as read on 9 Oct 2026.
  c_cust_cols constant text := 'date_of_birth date|deleted_at timestamp with time zone|email text|first_name text|full_name text not null|gender customer_gender|gender_other text|id uuid not null|is_active boolean not null|last_name text|notes text|occupation text|phone text not null|referred_by uuid|updated_at timestamp with time zone not null';
  -- The customers triggers it relies on, enabled.
  c_cust_trg constant text :=
       'CREATE TRIGGER customer_phone_audit AFTER UPDATE OF phone ON public.customers FOR EACH ROW EXECUTE FUNCTION audit_customer_phone_change()'
    || '|CREATE TRIGGER sync_customer_name BEFORE INSERT OR UPDATE ON public.customers FOR EACH ROW EXECUTE FUNCTION trg_sync_person_name()'
    || '|CREATE TRIGGER trg_customers_referral_date BEFORE INSERT OR UPDATE OF referred_by, referred_at ON public.customers FOR EACH ROW EXECUTE FUNCTION tg_customers_referral_date()'
    || '|CREATE TRIGGER trg_customers_set_updated_at BEFORE UPDATE ON public.customers FOR EACH ROW EXECUTE FUNCTION set_updated_at()'
    || '|CREATE TRIGGER trg_enforce_referral_ownership BEFORE INSERT OR UPDATE OF referred_by ON public.customers FOR EACH ROW EXECUTE FUNCTION enforce_referral_ownership()'
    || '|CREATE TRIGGER zz_normalize_current_customer_phone BEFORE INSERT OR UPDATE ON public.customers FOR EACH ROW EXECUTE FUNCTION normalize_current_customer_phone()';
  -- The two rules dropped, as read on 9 Oct 2026 (name|command|roles|using|check).
  c_rule_insert constant text := 'insert customers|INSERT|{authenticated}||(current_user_role() IS NOT NULL)';
  c_rule_update constant text := 'update customers|UPDATE|{authenticated}|(current_user_role() IS NOT NULL)|(current_user_role() IS NOT NULL)';

  v_path text := current_setting('search_path');
  v_claims text := current_setting('request.jwt.claims', true);
  r record; d text; v text; n int; k int; v_bad text;
  v_fns text[] := '{}'; v_defs text[] := '{}'; v_acl text[];
  v_table_new boolean; v_legacy_new boolean; v_adjust_new boolean;
  v_owner uuid; v_staff uuid; v_invman uuid; v_cust uuid; v_store uuid; v_at timestamptz; v_lot1 uuid; v_lot2 uuid; v_req uuid;
begin
  perform set_config('search_path', 'public', true);

  -- ── Guards: nothing changes unless all pass ──────────────────────────────
  -- The functions relied on, as read on 9 Oct 2026.
  for r in select * from (values
    ('require_active_staff(text[])', '877b3aa74cea559881979bb161c450e2'),
    ('normalize_customer_phone(text)', 'b2bfac910e0c9eff402ba44e19750bee'),
    ('write_audit_ex(text,uuid,text,jsonb,jsonb,text,text,uuid,text,text)', 'c705c733e213a27f0dc32d54322cc855'),
    ('can_manage_customer_credit()', 'a576249272a4c7fb68965d0f62649ed4'),
    ('is_owner_or_manager()', '125dec10ce33b84ff5fb40a9bd455235'),
    ('grant_customer_credit(uuid,text,numeric,text,uuid,uuid,date,text,text,text,date,uuid,jsonb)',
     'ac0de5530624ee533aacf93aec389910'),
    ('ensure_customer_wallet(uuid)', '8ef18daebbbe3c12f2024290ea8416e8'),
    ('trg_sync_person_name()', 'bdfc01a20c6d82672a24c694a0ea917b'),
    ('audit_customer_phone_change()', '414b5857bccb5b06d7ef3278dc754617'),
    ('enforce_referral_ownership()', '437c1677a8a319eb573f3e5132b4fd32'),
    ('normalize_current_customer_phone()', 'd05e8caea5d619372206a3191bc9e782'),
    ('tg_customers_referral_date()', '5ea2010a7b31efd4db32474723f814f6'),
    ('set_updated_at()', 'ffc2b9b80f7c977fb37f97b9c4d28802'),
    -- 414's settlements must be in: delete_customer reads what a referrer owes back.
    ('affiliate_referrer_balances()', '54ef098ba8f9e3d81bb45906c4607ab6'),
    ('affiliate_month_balances()', '84c0741e983c8f483d677353c732d891'),
    ('affiliate_payout_lock()', 'c410a35592ecae0ec9af516e5595f272')) x(fn, md5)
  loop
    if to_regprocedure('public.' || r.fn) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || r.fn))) <> r.md5 then
      raise exception '418: public.% is missing or not the version read on 9 Oct 2026. Re-read it from production and re-test before applying.', r.fn; end if;
  end loop;

  -- customers, as read on 9 Oct 2026: the columns and triggers relied on.
  select string_agg(a.attname || ' ' || format_type(a.atttypid, a.atttypmod) || case when a.attnotnull then ' not null' else '' end,
                    '|' order by a.attname) into v
    from pg_attribute a
   where a.attrelid = 'public.customers'::regclass and a.attnum > 0 and not a.attisdropped
     and a.attname in ('id', 'full_name', 'first_name', 'last_name', 'phone', 'email', 'date_of_birth', 'gender',
                       'gender_other', 'occupation', 'notes', 'is_active', 'referred_by', 'updated_at', 'deleted_at');
  if v is distinct from c_cust_cols then
    raise exception '418: public.customers is not shaped as read on 9 Oct 2026 (%)', v; end if;
  select string_agg(pg_get_triggerdef(t.oid), '|' order by t.tgname) into v
    from pg_trigger t
   where t.tgrelid = 'public.customers'::regclass and not t.tgisinternal and t.tgenabled = 'O'
     and t.tgname in ('customer_phone_audit', 'sync_customer_name', 'trg_customers_referral_date',
                      'trg_customers_set_updated_at', 'trg_enforce_referral_ownership',
                      'zz_normalize_current_customer_phone');
  if v is distinct from c_cust_trg then
    raise exception '418: the customers triggers relied on are not the ones read on 9 Oct 2026 (%)', v; end if;

  -- The rules on customers: the two to drop as read, or gone; nothing else
  -- that writes.
  select string_agg(p.policyname || '|' || p.cmd || '|' || p.roles::text || '|' || coalesce(p.qual, '') || '|'
                    || coalesce(p.with_check, ''), '#' order by p.policyname) into v
    from pg_policies p
   where p.schemaname = 'public' and p.tablename = 'customers' and p.cmd <> 'SELECT';
  if v is not null and v is distinct from c_rule_insert || '#' || c_rule_update then
    raise exception '418: the write rules on public.customers are not the ones read on 9 Oct 2026 (%)', v; end if;

  -- The changed functions: BEFORE (patched here) or AFTER (left alone).
  for r in select * from (values
    (c_quick_fn, '851b2d078f24668f17f2dd2f8b1bc1b9', c_quick_after,
     array[[c_quick_check_a, c_quick_check_r], [c_quick_ref_a, c_quick_ref_r], [c_quick_audit_a, c_quick_audit_r]]),
    (c_search_fn, '37cfdf902b98e800446211e9a4fdbabb', c_search_after,
     array[[c_search_q_a, c_search_q_r], [c_search_match_a, c_search_match_r], [c_search_ref_a, c_search_ref_r]]),
    (c_survey_fn, '900cfd200ddbdcb69ce87d3b6cdbc3e5', c_survey_after,
     array[[c_survey_a, c_survey_r]]),
    (c_delete_fn, '921fc8b248ed4bc72344440ae7368a71', c_delete_after,
     array[[c_delete_decl_a, c_delete_decl_r], [c_delete_check_a, c_delete_check_r],
           [c_delete_lock_a, c_delete_lock_r], [c_delete_open_a, c_delete_open_r]]),
    (c_phone_fn, 'd8a066be954bd7c7db9049139330d8b0', c_phone_after,
     array[[c_phone_a, c_phone_r]])
  ) x(fn, before_md5, after_md5, edits)
  loop
    if to_regprocedure('public.' || r.fn) is null then
      raise exception '418: public.% is missing', r.fn; end if;
    d := pg_get_functiondef(to_regprocedure('public.' || r.fn));
    v := md5(d);
    if v = r.after_md5 then
      raise notice '418: public.% is already this version; left alone', r.fn;
      continue;
    elsif v <> r.before_md5 then
      raise exception '418: public.% is not the version this was tested against (md5 %). Re-read it from production and re-test before applying.', r.fn, v;
    end if;
    for k in 1 .. array_length(r.edits, 1) loop
      n := (length(d) - length(replace(d, r.edits[k][1], ''))) / length(r.edits[k][1]);
      if n <> 1 then
        raise exception '418: anchor % of public.% was found % times, not once', k, r.fn, n; end if;
      d := replace(d, r.edits[k][1], r.edits[k][2]);
    end loop;
    if md5(d) <> r.after_md5 then
      v_bad := concat_ws('; ', v_bad, r.fn || ' built ' || md5(d)); end if;
    v_fns := v_fns || r.fn;
    v_defs := v_defs || d;
  end loop;

  -- The two credit functions: BEFORE (made again here) or AFTER (left alone).
  if to_regprocedure('public.' || c_legacy_fn) is null then
    raise exception '418: public.% is missing', c_legacy_fn; end if;
  v := md5(pg_get_functiondef(to_regprocedure('public.' || c_legacy_fn)));
  v_legacy_new := v <> c_legacy_after;
  if v_legacy_new and v <> c_legacy_before then
    raise exception '418: public.% is not the version this was tested against (md5 %). Re-read it from production and re-test before applying.', c_legacy_fn, v; end if;
  if to_regprocedure('public.' || c_adjust_fn) is null then
    raise exception '418: public.% is missing', c_adjust_fn; end if;
  v := md5(pg_get_functiondef(to_regprocedure('public.' || c_adjust_fn)));
  v_adjust_new := v <> c_adjust_after;
  if v_adjust_new and v <> c_adjust_before then
    raise exception '418: public.% is not the version this was tested against (md5 %). Re-read it from production and re-test before applying.', c_adjust_fn, v; end if;

  -- The new functions: missing, or already this version.
  for r in select * from (values (c_dob_fn, c_dob_def, c_dob_after), (c_update_fn, c_update_def, c_update_after)) x(fn, def, after_md5)
  loop
    if to_regprocedure('public.' || r.fn) is null then
      v_fns := v_fns || r.fn;
      v_defs := v_defs || r.def;
    elsif md5(pg_get_functiondef(to_regprocedure('public.' || r.fn))) <> r.after_md5 then
      raise exception '418: public.% exists and is not this migration''s version', r.fn;
    end if;
  end loop;

  -- One function of each name: no overload is added, none is left behind.
  select string_agg(p.oid::regprocedure::text, ', ') into v from pg_proc p
   where p.pronamespace = 'public'::regnamespace
     and p.proname in ('assert_customer_dob_change', 'update_customer', 'create_customer_quick', 'search_customers',
                       'customer_survey_overview', 'delete_customer', 'add_legacy_credit', 'adjust_customer_credit',
                       'change_customer_phone')
     and p.oid::regprocedure::text not in (c_dob_fn, c_update_fn, c_quick_fn, c_search_fn, c_survey_fn, c_delete_fn,
                                           c_legacy_fn, c_adjust_fn, c_phone_fn);
  if v is not null then
    raise exception '418: another function takes one of these names: %', v; end if;

  -- The table: missing, or already exactly this.
  v_table_new := to_regclass('public.customer_credit_entry_requests') is null;
  if not v_table_new then
    select string_agg(a.attname || ' ' || format_type(a.atttypid, a.atttypmod)
                      || case when a.attnotnull then ' not null' else '' end
                      || coalesce(' default ' || pg_get_expr(df.adbin, df.adrelid), ''), '|' order by a.attnum) into v
      from pg_attribute a left join pg_attrdef df on df.adrelid = a.attrelid and df.adnum = a.attnum
     where a.attrelid = 'public.customer_credit_entry_requests'::regclass and a.attnum > 0 and not a.attisdropped;
    if v is distinct from c_req_cols then
      raise exception '418: public.customer_credit_entry_requests exists and is not this migration''s (%)', v; end if;
    select string_agg(pg_get_constraintdef(c.oid), '|' order by pg_get_constraintdef(c.oid)) into v
      from pg_constraint c where c.conrelid = 'public.customer_credit_entry_requests'::regclass;
    if v is distinct from c_req_cons then
      raise exception '418: public.customer_credit_entry_requests has other constraints (%)', v; end if;
  elsif not v_legacy_new or not v_adjust_new then
    raise exception '418: the credit functions are in but public.customer_credit_entry_requests is missing';
  end if;

  -- The new texts are the tested ones.
  if md5(c_dob_def) <> c_dob_after then
    v_bad := concat_ws('; ', v_bad, c_dob_fn || ' text ' || md5(c_dob_def)); end if;
  if md5(c_update_def) <> c_update_after then
    v_bad := concat_ws('; ', v_bad, c_update_fn || ' text ' || md5(c_update_def)); end if;
  if md5(c_legacy_def) <> c_legacy_after then
    v_bad := concat_ws('; ', v_bad, c_legacy_fn || ' text ' || md5(c_legacy_def)); end if;
  if md5(c_adjust_def) <> c_adjust_after then
    v_bad := concat_ws('; ', v_bad, c_adjust_fn || ' text ' || md5(c_adjust_def)); end if;
  if v_bad is not null then
    raise exception '418: a text is not the tested one: %', v_bad; end if;

  -- The grants of the functions patched in place, to compare afterwards.
  select array_agg(p.oid::regprocedure::text || '=' || coalesce(p.proacl::text, '') order by p.oid::regprocedure::text)
    into v_acl from pg_proc p
   where p.pronamespace = 'public'::regnamespace
     and p.oid::regprocedure::text in (c_quick_fn, c_search_fn, c_survey_fn, c_delete_fn, c_phone_fn);

  -- ── Change ───────────────────────────────────────────────────────────────
  if v_table_new then
    create table public.customer_credit_entry_requests (
      request_id uuid primary key,
      entry_kind text not null check (entry_kind in ('opening_balance', 'adjustment')),
      customer_id uuid not null,
      entry_id uuid not null,
      created_by uuid references public.profiles(id),
      created_at timestamptz not null default now());
    comment on table public.customer_credit_entry_requests is
      '418: one row per request id of an opening balance (add_legacy_credit) or a credit adjustment (adjust_customer_credit), naming what it recorded, so a repeated request is recorded once. Written by those two functions only.';
  end if;
  alter table public.customer_credit_entry_requests enable row level security;
  revoke all on table public.customer_credit_entry_requests from public, anon, authenticated, service_role;
  grant select on table public.customer_credit_entry_requests to service_role;

  if v_legacy_new then
    drop function public.add_legacy_credit(uuid,text,numeric,date,uuid,text,text,date,uuid);
    execute c_legacy_def;
    revoke all on function public.add_legacy_credit(uuid,text,numeric,date,uuid,text,text,date,uuid) from public, anon;
    grant execute on function public.add_legacy_credit(uuid,text,numeric,date,uuid,text,text,date,uuid)
      to authenticated, service_role;
  end if;
  if v_adjust_new then
    drop function public.adjust_customer_credit(uuid,text,text,numeric,text,text,date,text,uuid,uuid);
    execute c_adjust_def;
    revoke all on function public.adjust_customer_credit(uuid,text,text,numeric,text,text,date,text,uuid,uuid)
      from public, anon;
    grant execute on function public.adjust_customer_credit(uuid,text,text,numeric,text,text,date,text,uuid,uuid)
      to authenticated, service_role;
  end if;

  -- assert_customer_dob_change first: update_customer calls it.
  for k in 1 .. coalesce(array_length(v_fns, 1), 0) loop
    if v_fns[k] = c_dob_fn then
      execute v_defs[k];
      revoke all on function public.assert_customer_dob_change(uuid,date,text) from public, anon, authenticated;
      grant execute on function public.assert_customer_dob_change(uuid,date,text) to service_role;
    end if;
  end loop;
  for k in 1 .. coalesce(array_length(v_fns, 1), 0) loop
    if v_fns[k] = c_dob_fn then
      continue;
    end if;
    execute v_defs[k];
    if v_fns[k] = c_update_fn then
      revoke all on function public.update_customer(uuid,jsonb,text,timestamptz) from public, anon;
      grant execute on function public.update_customer(uuid,jsonb,text,timestamptz) to authenticated, service_role;
    end if;
  end loop;

  -- Staff no longer write the table; the functions above do.
  drop policy if exists "insert customers" on public.customers;
  drop policy if exists "update customers" on public.customers;
  revoke insert, update on table public.customers from anon, authenticated;

  -- ── As tested ────────────────────────────────────────────────────────────
  v_bad := null;
  for r in select * from (values
    (c_dob_fn, c_dob_after), (c_update_fn, c_update_after), (c_quick_fn, c_quick_after),
    (c_search_fn, c_search_after), (c_survey_fn, c_survey_after), (c_delete_fn, c_delete_after),
    (c_legacy_fn, c_legacy_after), (c_adjust_fn, c_adjust_after), (c_phone_fn, c_phone_after)) x(fn, after_md5)
  loop
    v := md5(pg_get_functiondef(to_regprocedure('public.' || r.fn)));
    if v <> r.after_md5 then
      v_bad := concat_ws('; ', v_bad, r.fn || ' ' || v); end if;
  end loop;
  if v_bad is not null then
    raise exception '418: installed with md5s other than the tested ones: %', v_bad; end if;
  if (select array_agg(p.oid::regprocedure::text || '=' || coalesce(p.proacl::text, '') order by p.oid::regprocedure::text)
        from pg_proc p
       where p.pronamespace = 'public'::regnamespace
         and p.oid::regprocedure::text in (c_quick_fn, c_search_fn, c_survey_fn, c_delete_fn, c_phone_fn)) is distinct from v_acl then
    raise exception '418: the grants of the patched functions changed'; end if;

  -- ── Grants, by the catalogue ─────────────────────────────────────────────
  if has_function_privilege('anon', 'public.' || c_dob_fn, 'execute')
     or has_function_privilege('authenticated', 'public.' || c_dob_fn, 'execute')
     or not has_function_privilege('service_role', 'public.' || c_dob_fn, 'execute') then
    raise exception '418: public.% is not the service role''s alone', c_dob_fn; end if;
  foreach v in array array[c_update_fn, c_legacy_fn, c_adjust_fn] loop
    if has_function_privilege('anon', 'public.' || v, 'execute')
       or not has_function_privilege('authenticated', 'public.' || v, 'execute')
       or not has_function_privilege('service_role', 'public.' || v, 'execute') then
      raise exception '418: public.% is not staff''s and the service role''s alone', v; end if;
  end loop;
  if exists (select 1 from pg_proc p, aclexplode(p.proacl) a
              where p.oid in (to_regprocedure('public.' || c_dob_fn), to_regprocedure('public.' || c_update_fn),
                              to_regprocedure('public.' || c_legacy_fn), to_regprocedure('public.' || c_adjust_fn))
                and a.grantee = 0) then
    raise exception '418: a new function is granted to PUBLIC'; end if;
  if not (select c.relrowsecurity from pg_class c where c.oid = 'public.customer_credit_entry_requests'::regclass)
     or exists (select 1 from pg_policies p where p.schemaname = 'public' and p.tablename = 'customer_credit_entry_requests')
     or has_table_privilege('anon', 'public.customer_credit_entry_requests', 'select,insert,update,delete,truncate,references,trigger')
     or has_table_privilege('authenticated', 'public.customer_credit_entry_requests', 'select,insert,update,delete,truncate,references,trigger')
     or has_table_privilege('service_role', 'public.customer_credit_entry_requests', 'insert,update,delete,truncate,references,trigger')
     or not has_table_privilege('service_role', 'public.customer_credit_entry_requests', 'select') then
    raise exception '418: public.customer_credit_entry_requests is not closed as tested'; end if;
  foreach v in array array['anon', 'authenticated'] loop
    if has_table_privilege(v, 'public.customers', 'insert') or has_table_privilege(v, 'public.customers', 'update')
       or has_any_column_privilege(v, 'public.customers', 'insert') or has_any_column_privilege(v, 'public.customers', 'update') then
      raise exception '418: % may still write public.customers', v; end if;
  end loop;
  if not has_table_privilege('authenticated', 'public.customers', 'select')
     or not exists (select 1 from pg_policies p where p.schemaname = 'public' and p.tablename = 'customers'
                     and p.policyname = 'read customers' and p.cmd = 'SELECT')
     or exists (select 1 from pg_policies p where p.schemaname = 'public' and p.tablename = 'customers'
                 and p.cmd <> 'SELECT') then
    raise exception '418: the rules on public.customers are not as tested (read stays, the write rules are gone)'; end if;

  -- ── Behaviour, inside a block that is always undone ──────────────────────
  -- Made-up people (@sig.invalid) and a made-up customer and store; nothing
  -- is printed and no row remains.
  begin
    insert into auth.users (id, email) values (gen_random_uuid(), '418-check-owner-' || gen_random_uuid() || '@sig.invalid')
      returning id into v_owner;
    insert into auth.users (id, email) values (gen_random_uuid(), '418-check-staff-' || gen_random_uuid() || '@sig.invalid')
      returning id into v_staff;
    insert into auth.users (id, email) values (gen_random_uuid(), '418-check-invman-' || gen_random_uuid() || '@sig.invalid')
      returning id into v_invman;
    insert into public.profiles (id, full_name, email, role, is_active)
    select u.id, '418 check', u.email, x.role::public.user_role, true
      from auth.users u join (values (v_owner, 'owner'), (v_staff, 'staff'), (v_invman, 'inventory_manager')) x(id, role)
        on x.id = u.id;
    insert into public.stores (name, code, country_code) values ('418 check', '418CHK', 'SG') returning id into v_store;
    perform set_config('request.jwt.claims', '', true);
    insert into public.customers (first_name, last_name, phone) values ('418', 'Check', '+6591418001')
      returning id into v_cust;

    -- Staff: fill in a missing date of birth; refused changing it; refused
    -- writing the table; a phone typed with a space is found.
    perform set_config('request.jwt.claims', json_build_object('sub', v_staff, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    select c.updated_at into v_at from public.customers c where c.id = v_cust;
    perform public.update_customer(v_cust, '{"date_of_birth": "1990-01-02"}'::jsonb, null, v_at);
    begin
      perform public.update_customer(v_cust, '{"date_of_birth": "1990-01-03"}'::jsonb, '418 check', null);
      raise exception '418: a member of staff changed a date of birth already filled in';
    exception when insufficient_privilege then null;
    end;
    begin
      insert into public.customers (full_name, phone) values ('418 direct', '+6591418002');
      raise exception '418: a staff login still adds customers to the table directly';
    exception when insufficient_privilege then null;
    end;
    begin
      update public.customers set notes = '418 direct' where id = v_cust;
      raise exception '418: a staff login still changes customers in the table directly';
    exception when insufficient_privilege then null;
    end;
    if not exists (select 1 from public.search_customers('9141 8001', null, 50, 0) s where s.id = v_cust)
       or not exists (select 1 from public.search_customers('+65 9141-8001', null, 50, 0) s where s.id = v_cust) then
      raise exception '418: a phone typed with a space or +65 was not found'; end if;
    execute 'reset role';

    -- An Inventory Manager: refused adding, editing and changing a phone.
    perform set_config('request.jwt.claims', json_build_object('sub', v_invman, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    begin
      perform public.update_customer(v_cust, '{"notes": "418 check"}'::jsonb, null, null);
      raise exception '418: an Inventory Manager edited a customer';
    exception when insufficient_privilege then null;
    end;
    begin
      perform public.create_customer_quick('418', 'Invman', '+6591418003');
      raise exception '418: an Inventory Manager added a customer';
    exception when insufficient_privilege then null;
    end;
    begin
      perform public.change_customer_phone(v_cust, '+6591418004', '418 check');
      raise exception '418: an Inventory Manager changed a customer''s phone';
    exception when insufficient_privilege then null;
    end;
    execute 'reset role';

    -- An Owner: the change needs a reason, and is recorded old and new.
    perform set_config('request.jwt.claims', json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    begin
      perform public.update_customer(v_cust, '{"date_of_birth": "1990-01-03"}'::jsonb, null, null);
      raise exception '418: a date of birth was changed without a reason';
    exception when raise_exception then
      if sqlerrm not like 'A reason is required%' then raise; end if;
    end;
    perform public.update_customer(v_cust, '{"date_of_birth": "1990-01-03"}'::jsonb, '418 check', null);
    -- An opening balance sent twice with one request id.
    v_req := gen_random_uuid();
    v_lot1 := public.add_legacy_credit(v_cust, 'legacy', 10, public.sg_today(), v_store, null, '418 check', null, v_req);
    v_lot2 := public.add_legacy_credit(v_cust, 'legacy', 10, public.sg_today(), v_store, null, '418 check', null, v_req);
    execute 'reset role';
    if (select c.date_of_birth from public.customers c where c.id = v_cust) is distinct from date '1990-01-03'
       or not exists (select 1 from public.audit_logs a
                       where a.record_id = v_cust and a.action = 'customer_updated' and a.changed_by = v_owner
                         and a.old_data->>'date_of_birth' = '1990-01-02' and a.new_data->>'date_of_birth' = '1990-01-03'
                         and a.reason = '418 check')
       or (select count(*) from public.audit_logs a where a.record_id = v_cust and a.action = 'customer_updated') <> 2 then
      raise exception '418: the date of birth changes were not saved with their old and new values'; end if;
    if v_lot1 is distinct from v_lot2
       or (select count(*) from public.customer_credit_lots l where l.customer_id = v_cust) <> 1 then
      raise exception '418: an opening balance sent twice was recorded twice'; end if;
    raise exception using errcode = 'P0418', message = '418: check done, undone';
  exception when sqlstate 'P0418' then null;
  end;
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);

  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $mig$;
