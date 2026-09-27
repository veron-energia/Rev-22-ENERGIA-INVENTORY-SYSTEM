# Phase 6A — Profile fields, Manager store access, location phones

First sub-phase of your Phase 6 requirements. Foundation only — invoice/staff
flows, customer form changes, and print updates come in 6B onward.

## What changed (per your three decisions)

1. **Manager now has unconditional store access**, same as Owner and Admin —
   no more per-store assignment needed for Manager.
2. **User profiles** gain Work Phone, Personal Phone, and Personal Email.
   The existing Email column is now labeled **"Work Email"** in the UI — it
   already is the Supabase Auth login address, so no schema change was
   needed for that. Editing it in the Edit User form is disabled with a note
   pointing to the Supabase dashboard, since changing the actual login
   requires that manual step (per your decision — no Edge Function).
   Work Phone / Personal Phone / Personal Email are **required in the form**
   for Staff, Owner, and Manager roles (Admin and Inventory Manager are not
   required yet, per spec).
3. **Stores and Warehouses** each gain a required Phone field, shown in
   their tables and required on Add/Edit — same pattern as the existing
   required Address field.

## Setup
1. Run **`supabase/24_phase6a_profile_location_fields.sql`** (after 23b).
2. Replace `src/`, then `npm install && npm run dev`.

## Note on existing data
Existing profiles/stores/warehouses will have blank Work Phone / Personal
Phone / Personal Email / Store Phone / Warehouse Phone until you edit and
save them once — the new columns are nullable at the database level (so
nothing broke on migration), and "required" is enforced by the forms going
forward. Please open Users, Stores, and Warehouses and fill these in for your
real records — in particular, set your real store/warehouse phone number
(you mentioned 63372768 for your center).

---

## TEST CHECKLIST — Phase 6A

1. Users page -> Edit a Staff/Owner/Manager user -> Work Phone, Personal
   Phone, Personal Email are required; saving without them shows a clear
   error. Work Email field is visible but disabled with the dashboard note.
2. Edit an Admin or Inventory Manager user -> the three fields are NOT
   required (can save blank).
3. Users list shows a new "Work Phone" column.
4. Stores -> Add/Edit a store -> Phone is required alongside Address; list
   shows the new Phone column.
5. Warehouses -> same as above.
6. Manager login -> previously if a Manager wasn't assigned to a store, they
   couldn't create invoices for it. Confirm a Manager can now select ANY
   active store in New Invoice regardless of assignment.
7. Staff/Owner/Admin store access is unchanged (Staff still needs
   assignment; Owner/Admin still unconditional).

## Next: 6B - Customer profile changes (remove address; add DOB, gender with
custom "Other", occupation)
