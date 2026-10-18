-- 431_audit_entries_record_their_module.sql
--
-- WHAT WAS WRONG (the audit of 9 Oct 2026: the follow-up 428 left open)
--
--   New audit entries kept arriving with no module. write_audit(), which 42
--   server functions call (invoices, commissions, stock adjustments, stock
--   in, vouchers, rentals, customers, settings and more), never saved one.
--   write_audit_ex() saves the module its caller passes, and none when the
--   caller passes none. Seven functions write audit_logs themselves and save
--   none either (staff logins blocked and unblocked; staff invitations made,
--   accepted and cancelled; therapy services saved and archived; a therapy
--   reward tier mapped). On 9 Oct 2026 production held 5,045 entries; 2,380
--   had no module, 137 of them from the seven days before. Since 428 the
--   Audit Log takes a missing module from the entry's table when it reads
--   it, and marks it "from table".
--
--   One module also went by two names. 52 entries (12 Aug to 7 Oct) were
--   saved as "commission" and 11 (since 18 Sep) as "commissions", and the
--   516 commission entries with no module are shown as "commissions". The
--   Audit Log's module filter listed both names, and choosing one left out
--   the other's entries.
--
-- THE RULES (owner, 9 Oct 2026)
--
--   1. New audit entries record their module. write_audit() sets it, from the
--      entry's table, with the same table-to-module list the Audit Log has
--      used since 428.
--   2. "commission" and "commissions" show as one name, "commissions", in the
--      Audit Log's module filter.
--   3. Existing audit entries are evidence: none is rewritten. The two names
--      are merged when the log is read, not in the table.
--   4. (owner, 18 Oct 2026) Entries of the therapy voucher-rights routine
--      (apply_therapy_voucher_rights_retrospectively, which writes rows for
--      table customer_reward_vouchers) are filed under "therapy", and
--      FOC-reason changes (table foc_reasons) under "invoices". Other
--      voucher-rights entries, already saved as "refunds" or "invoices", stay
--      as they are, and no saved entry is changed.
--
-- WHAT THIS DOES
--
--   * audit_module(p_module, p_table) (new, internal): the module an entry is
--     filed under. A module given is kept, with "commission" read as
--     "commissions". With none, it comes from the table: 428's list, plus the
--     tables audit writers use that 428 did not name and whose other writers
--     already save one clear module (or that sit next to a table in 428's
--     list): staff commission payouts and affiliate deduction settlements:
--     commissions; voucher store stock: inventory; products and credit
--     package spending rules: catalogue; therapy entitlements: therapy;
--     special sales: special; TikTok status mappings: tiktok_import; staff
--     invitations and store assignments (420): users; and, by rule 4, FOC
--     reasons: invoices, and customer reward vouchers: therapy. Any other
--     table is its own module, as in 428. Only the therapy voucher-rights
--     routine (apply_therapy_voucher_rights_retrospectively, through
--     write_audit) writes customer_reward_vouchers entries with no module;
--     its other writers pass one, which is kept (refund_invoice_recorded
--     "refunds"; correct_invoice and snapshot_therapy_voucher_issue
--     "invoices"). foc_reasons entries come from upsert_foc_reason and
--     set_foc_reason_active, through write_audit (production and every batch
--     of this round, read 18 Oct 2026). None of the added tables has an
--     entry without a module today (read again 18 Oct 2026: the 5
--     customer_reward_vouchers entries are all "refunds", foc_reasons has
--     none), so no existing entry is shown differently because of them.
--     Two things follow from rule 4 (review of 18 Oct 2026). The mapping is
--     by table: any later customer_reward_vouchers entry saved with no
--     module, whoever writes it, is filed under "therapy", so a later writer
--     whose entry is not about therapy must pass its own module through
--     write_audit_ex. And FOC invoices keep their own module "foc" (40
--     entries on 18 Oct 2026: invoice_foc_created 34, 11 Aug to 10 Oct;
--     invoice_foc_confirmed 6, 25 Aug to 1 Oct), as every module name already
--     saved is kept; FOC-reason changes go under "invoices", so a filter by
--     "foc" does not show them.
--   * write_audit() (replaced; grants kept): saves the module of its table.
--   * trg_audit_logs_fill_module() and its trigger audit_logs_fill_module
--     (new): before an entry is inserted with no module, it is given its
--     table's. This covers write_audit_ex() when its caller passes none, and
--     the functions that write audit_logs themselves (staff_login_sync,
--     invite_user_begin/accept/cancel, upsert_therapy_service,
--     archive_therapy_service, therapy_map_entitlement_tier, and any added
--     later), without changing them. Only the new row's empty module is set.
--   * audit_log_page() (patched; grants kept): the module shown, filtered
--     and offered as a choice is audit_module() of the stored module and the
--     table, so "commission" entries show and filter as "commissions", and
--     the filter lists one name. Asking for either name finds both. Its rows
--     and export show the same merged name so they agree with the filter
--     (this migration's choice; the stored value stays "commission"). An
--     entry saved without a module is still marked "from table".
--
--   On production after this, the Audit Log shows 29 module names instead of
--   30; the 52 "commission" entries show as "commissions" (579 in all), and
--   no other existing entry is shown under another module. Read again on
--   18 Oct 2026 (5,347 entries), with rule 4: 30 names become 29, the 54
--   "commission" entries show as "commissions" (610 in all), and still no
--   other existing entry is shown under another module.
--
-- NOT CHANGED
--
--   * public.audit_logs rows: none is written, changed or removed. Its
--     columns, read rule, grants, index and the invoice date lock trigger
--     stay.
--   * write_audit_ex(): its text, grants and md5 stay (415 checked that it is
--     the version read on 9 Oct 2026 when it was applied, and 417 and 418,
--     not yet applied, check it too). A module its caller passes is saved as
--     passed, "commission" included; only an empty one is filled, by the
--     trigger.
--   * Who may read the Audit Log (active Owners, Admins and Managers), and
--     428's paging, as-of time, filters and text search.
--   * write_audit() stays internal (service role only, as since 406); its
--     arguments and result are the same.
--   * The other names that differ by a letter ("invoice"/"invoices",
--     "customer"/"customers", "exchange"/"exchanges", "affiliate"/
--     "affiliates", "survey"/"surveys") stay separate: the owner's answer was
--     about commissions only.
--   * The affiliate claim checks (378, 379) count only rows of
--     affiliate_accounts and affiliate_account_claims saved with module
--     "affiliate", which only write_audit_ex writes, when asked to. A module
--     taken from those tables is the table's own name, so a row written
--     through write_audit, or with no module, still never counts.
--   * invoice_date_evidence() puts the module before the reason in an
--     invoice's history, as it already did for write_audit_ex entries. New
--     write_audit entries on an invoice add "invoices" there;
--     plan_invoice_date_recovery() looks for words such as "import" and
--     "migrat", which no module taken from the invoices table holds.
--   * The 156 entries with no role, and the direct writers that save none,
--     are left as they are (a separate gap).
--
-- SAFETY
--
--   Apart from the lock timeout this is one DO block, so it is atomic. It
--   refuses unless 406 is in (require_active_staff at its AFTER md5) and
--   current_user_role() is the version read on 9 Oct 2026; audit_logs has
--   the columns write_audit and the trigger use, as read that day; each
--   changed function is the production version (BEFORE) or already this
--   migration's (AFTER, left alone, so a re-run changes nothing); the new
--   functions are missing or already this version; no other function takes
--   any of these names (the API picks an overload by name); the trigger is
--   missing or already exactly this one; every anchor occurs exactly once;
--   and every text has its AFTER md5 before it is installed. CREATE OR
--   REPLACE with the same arguments and results keeps the owner and grants.
--   Adding the trigger holds new audit entries back for as long as it takes
--   (a moment); the lock timeout stops it waiting behind a long write.
--   Afterwards: the md5s, the trigger (enabled), the grants of the changed
--   functions as before, and the new functions callable by the service role
--   only. Then, inside a block that is always undone, a made-up Owner (an
--   @sig.invalid login) and made-up entries: write_audit files a staff
--   commission under "commissions", an affiliate account under its own
--   name, a customer reward voucher under "therapy" and a FOC reason under
--   "invoices" (rule 4); write_audit_ex keeps "commission", "affiliate" and
--   a voucher's "refunds" as passed and files an invoice with no module
--   under "invoices"; an entry inserted with
--   no module is filed under its table's, and one with a module keeps it; an
--   entry from before this (trigger off) keeps no module and is shown "from
--   table"; signed in, the Owner finds "commission" and "commissions" entries
--   under either name, shown as one, and the filter's choices hold no
--   "commission"; filtering by "invoices", "therapy" and "refunds" finds the
--   rule 4 entries. Nothing is printed and no row remains.
--
-- BEFORE (production, 9 Oct 2026, after 414, 421 and 428, read again on
-- 10 Oct after 415; md5 of pg_get_functiondef, search_path public):
--   changed
--   write_audit(text,uuid,text,jsonb,jsonb)                          19cd6b07bdbb6c73c26fb8aa83d2463e
--   audit_log_page(date,date,text,text,uuid,text,integer,integer,timestamp with time zone,boolean)
--                                                                    1b9054e6e243a81e640f0a2a4b18202e
--   relied on, not changed
--   require_active_staff(text[])                                     877b3aa74cea559881979bb161c450e2  (406)
--   current_user_role()                                              519b0a33a3548f970c5d585b6e76a389
--   read, not relied on, not changed
--   write_audit_ex(text,uuid,text,jsonb,jsonb,text,text,uuid,text,text)
--                                                                    c705c733e213a27f0dc32d54322cc855
--   lock_invoice_date_history() (the other trigger on audit_logs)    aeb1a3b86377f511af6b9a7d6d364a2e
--   affiliate_claim_link_check(uuid,uuid)                            251b1bd9f7175301750d65be4dd01b0e
--   affiliate_pending_claims()                                       7ab9d3c4edf81bac11c018a4048e6c8c
--   affiliate_rejected_claims()                                      d09d12ce05cc42f1bc5a5f41aeb8cc03
--   complete_affiliate_onboarding(text,text,text,boolean)            9ff0fd280f4a46eddb2446523d500233
--   invoice_date_evidence(uuid)                                      af2e7959c6dfdf8a5665ba56697b0e25
--   plan_invoice_date_recovery(jsonb)                                9ce36dbfe1fe9b56f47b81ceae006be0
--   restore_record(text,uuid)                                        387c5316b1a4621942edce86f7899962
--   new: audit_module(text,text), trg_audit_logs_fill_module() and the trigger
--   audit_logs_fill_module (all missing)
--   public function fingerprint (production after 414, 421 and 428)  897ad364eff917861989315bb2fa0e43
--   and after 415 too (applied 10 Oct 2026, 01:04 UTC)               566e76f702c89c9846968e6fdd89cc45
--   (415 changes none of the functions above; not guarded: only the md5s
--   above and the columns are)
-- AFTER (for later guards; audit_module's is new on 18 Oct 2026 with rule 4,
-- it was ae5f64054d37c528eb278d38e2464e1c before; the other three are as
-- they were):
--   audit_module(text,text)                                          daf0c43e9e9578e78048b2f6d7cba57e
--   trg_audit_logs_fill_module()                                     417a84925a3e465bcc9f11f7c13bb673
--   write_audit(text,uuid,text,jsonb,jsonb)                          b194f839993670c5b5dd28e934c2a829
--   audit_log_page(date,date,text,text,uuid,text,integer,integer,timestamp with time zone,boolean)
--                                                                    39d56b58e58da2005e0243df601721ee
--   write_audit_ex(text,uuid,text,jsonb,jsonb,text,text,uuid,text,text)
--                                                                    c705c733e213a27f0dc32d54322cc855  (unchanged)
--   public function fingerprint, with 431 the only change after 428
--                                                                    057373e661e80dfc8fa09d8059d08188
--   with 415 and 431 the only changes after 428                      63ef83b0547598991366b4dd7ff75069
--   production now (18 Oct 2026, after 433: ff637c8e7adc37a4892a6bf361290c4b,
--   1244 functions), plus 431                                        0f7776d47a309d5261fe491a62538523
--   production now, plus 420 then 431 (the planned order)            e14ee98d0c03a4bdb368a95b50842209
--   (worked out on copies of production after 428, after 415, and of
--   production on 18 Oct; other migrations of this round change it too; the
--   md5s above are the guards)
--
-- DEPLOY ORDER: after 420, when 420 goes in this round. 420 (not yet applied)
-- refuses unless write_audit() is the version read on 9 Oct 2026
-- (19cd6b07), which this replaces; nothing 431 checks is changed by 420, so
-- 420 then 431 works, and so does 431 alone. If 431 is in first, 420 stops
-- with "420: write_audit is not the version read on 9 Oct 2026; re-read and
-- re-test" and changes nothing; then 420's guard must also accept
-- write_audit's AFTER md5 above (b194f839) before it is applied. 420's own
-- DEPLOY ORDER says the same. 417 and 418 (not yet applied) check
-- write_audit_ex(), which this leaves alone: any order. 415 is in already
-- (10 Oct) and was tested with 431 on top. 423 and 429 (not live) rebuild
-- some of the functions that write audit_logs themselves; the trigger covers
-- them in whichever order they land. The Audit Log page needs no change: it
-- shows the module audit_log_page returns. 430 (not yet applied, last of
-- this round) checks audit_module at its AFTER md5 above, daf0c43e since
-- 18 Oct 2026: a 430 that still names the earlier ae5f6405 refuses after
-- this 431 ("430: public.audit_module(text,text) is not as batch 431 (B14b)
-- leaves it") and must be moved to daf0c43e first.
--
-- Test: scripts/audit-log/tests/audit-module.sql (this migration, applied or
-- re-run inside it: every writer, the merged name, rule 4 with the therapy
-- voucher-rights routine and the two FOC-reason routines called for real,
-- "foc" kept apart from "invoices", entries already saved left alone, the
-- grants, a re-run, and a refusal for each of 8 databases it was not tested
-- against),
-- scripts/audit-log/tests/audit-log-page.sql (428's paging and filters, with
-- entries from before 431 saved with the trigger off),
-- scripts/affiliate-claims/tests/staff-claims.sql and reject-protects.sql
-- (a write_audit row still never counts), scripts/permissions/tests/
-- function-grants.sql and staff-only-functions.sql.

set lock_timeout = '5s';

do $mig$
declare
  -- ── audit_module: the module an entry is filed under (new, internal) ─────
  c_module_def constant text := $def$CREATE OR REPLACE FUNCTION public.audit_module(p_module text, p_table text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  -- 431: the module an audit entry is filed under (owner, 9 Oct 2026). A
  -- module given with the entry is kept, with 'commission' read as
  -- 'commissions': one name for one module. With none, it is taken from the
  -- entry's table, as the Audit Log has shown since 428; a table not listed
  -- is its own module. The affiliate claim checks count only rows of
  -- affiliate_accounts and affiliate_account_claims with module 'affiliate';
  -- taken from the table, those rows' module is the table's own name, so a
  -- row saved with no module never counts there. Owner, 18 Oct 2026: FOC
  -- reasons are filed under 'invoices', and the therapy voucher-rights
  -- routine's customer_reward_vouchers entries (saved with no module) under
  -- 'therapy'; voucher entries saved with a module ('refunds', 'invoices')
  -- keep it.
  select case
    when p_module = 'commission' then 'commissions'
    when p_module is not null then p_module
    when p_table in ('invoices', 'foc_reasons') then 'invoices'
    when p_table in ('commissions', 'commission_payouts', 'staff_commissions', 'staff_commission_payouts',
                     'affiliate_deduction_settlements') then 'commissions'
    when p_table in ('inventory_adjustment', 'warehouse_inventory', 'special_product_stock',
                     'voucher_store_stock') then 'inventory'
    when p_table in ('vouchers', 'credit_packages', 'promotion_items', 'unlimited_therapy_packages',
                     'products', 'credit_package_spending_rules') then 'catalogue'
    when p_table in ('therapy_services', 'therapy_entitlements', 'customer_reward_vouchers') then 'therapy'
    when p_table in ('customers', 'customer_source_options') then 'customers'
    when p_table = 'transfer_requests' then 'transfers'
    when p_table = 'product_exchanges' then 'exchanges'
    when p_table = 'rentals' then 'rentals'
    when p_table = 'special_sales' then 'special'
    when p_table = 'tiktok_status_mappings' then 'tiktok_import'
    when p_table = 'app_settings' then 'settings'
    when p_table in ('profiles', 'user_invitations', 'user_store_assignments') then 'users'
    else p_table
  end
$function$
$def$;

  -- ── the trigger's function: an entry saved with no module (new) ──────────
  c_fill_def constant text := $def$CREATE OR REPLACE FUNCTION public.trg_audit_logs_fill_module()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  -- 431: a new audit entry saved with no module is filed under its table's
  -- (audit_module), whoever wrote it: write_audit_ex with none given, or a
  -- server function that writes audit_logs itself (staff logins,
  -- invitations, therapy services and more). Only the new row's empty module
  -- is set; nothing else in it is changed, and no saved entry is touched.
  if new.module is null then
    new.module := public.audit_module(null, new.table_name);
  end if;
  return new;
end
$function$
$def$;

  -- ── write_audit: records its table's module (replaced whole) ─────────────
  c_wa_def constant text := $def$CREATE OR REPLACE FUNCTION public.write_audit(p_table text, p_record uuid, p_action text, p_old jsonb, p_new jsonb)
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- 431: the entry records its module, taken from its table (audit_module).
  insert into public.audit_logs (table_name, record_id, action, old_data, new_data, changed_by, actor_role, module)
  values (p_table, p_record, p_action, p_old, p_new, auth.uid(), public.current_user_role()::text,
          public.audit_module(null, p_table));
$function$
$def$;

  -- ── audit_log_page: one module name (patched) ────────────────────────────
  c_page_a1 constant text := $q$  -- Module: the one stored with the entry. Entries saved without one (all of
  -- write_audit()'s) have it taken from the table here, at read time, and
  -- marked so. The entries themselves are never changed: they are the evidence.
$q$;
  c_page_r1 constant text := $q$  -- Module: the one stored with the entry, with 'commission' shown as
  -- 'commissions' (431: one name). Entries saved without one (write_audit()'s
  -- before 431) have it taken from the table here, at read time, and marked
  -- so. audit_module holds the rule; a module asked for is read the same way.
  -- The entries themselves are never changed: they are the evidence.
$q$;
  c_page_a2 constant text := $q$           coalesce(a.module, case
             when a.table_name = 'invoices' then 'invoices'
             when a.table_name in ('commissions', 'commission_payouts', 'staff_commissions') then 'commissions'
             when a.table_name in ('inventory_adjustment', 'warehouse_inventory', 'special_product_stock') then 'inventory'
             when a.table_name in ('vouchers', 'credit_packages', 'promotion_items', 'unlimited_therapy_packages') then 'catalogue'
             when a.table_name = 'therapy_services' then 'therapy'
             when a.table_name in ('customers', 'customer_source_options') then 'customers'
             when a.table_name = 'transfer_requests' then 'transfers'
             when a.table_name = 'product_exchanges' then 'exchanges'
             when a.table_name = 'rentals' then 'rentals'
             when a.table_name = 'app_settings' then 'settings'
             when a.table_name = 'profiles' then 'users'
             else a.table_name end) as module,
$q$;
  c_page_r2 constant text := $q$           public.audit_module(a.module, a.table_name) as module,
$q$;
  c_page_a3 constant text := $q$       and (p_module is null or e.module = p_module)
$q$;
  c_page_r3 constant text := $q$       and (p_module is null or e.module = public.audit_module(p_module, null))
$q$;

  c_module_after constant text := 'daf0c43e9e9578e78048b2f6d7cba57e';
  c_fill_after   constant text := '417a84925a3e465bcc9f11f7c13bb673';
  c_wa_after     constant text := 'b194f839993670c5b5dd28e934c2a829';
  c_page_after   constant text := '39d56b58e58da2005e0243df601721ee';
  c_staff_406    constant text := '877b3aa74cea559881979bb161c450e2';
  c_role_md5     constant text := '519b0a33a3548f970c5d585b6e76a389';
  c_trigger      constant text := 'CREATE TRIGGER audit_logs_fill_module BEFORE INSERT ON public.audit_logs FOR EACH ROW WHEN ((new.module IS NULL)) EXECUTE FUNCTION trg_audit_logs_fill_module()';
  -- The columns of audit_logs write_audit and the trigger use, as read on 9 Oct 2026.
  c_cols constant text := 'action text not null|actor_role text|changed_by uuid|module text|new_data jsonb|old_data jsonb|record_id uuid|table_name text not null';
  c_page_sig constant text := 'audit_log_page(date,date,text,text,uuid,text,integer,integer,timestamp with time zone,boolean)';
  c_changed constant text[] := array[
    'write_audit(text,uuid,text,jsonb,jsonb)',
    'audit_log_page(date,date,text,text,uuid,text,integer,integer,timestamp with time zone,boolean)'];

  v_path text := current_setting('search_path');
  v_claims text := current_setting('request.jwt.claims', true);
  r record; d text; v text; n int; k int; i int; v_bad text;
  v_fns text[] := '{}'; v_defs text[] := '{}'; v_acl text[];
  v_trigger_new boolean;
  -- the behaviour check
  v_owner uuid; v_mark text; j jsonb; v_rows text;
begin
  -- The definitions are read and compared with public alone on the search
  -- path, as they were read on 9 Oct 2026.
  perform set_config('search_path', 'public', true);

  -- ── Guards, anchors and texts: nothing is installed unless all pass ──────
  -- 406 is in, and the role write_audit records is read as on 9 Oct 2026.
  if to_regprocedure('public.require_active_staff(text[])') is null
     or md5(pg_get_functiondef('public.require_active_staff(text[])'::regprocedure)) <> c_staff_406 then
    raise exception '431: 406 is not in (require_active_staff(text[]) is not 406''s version); apply 406 first'; end if;
  if to_regprocedure('public.current_user_role()') is null
     or md5(pg_get_functiondef('public.current_user_role()'::regprocedure)) <> c_role_md5 then
    raise exception '431: public.current_user_role() is missing or not the version read on 9 Oct 2026. Re-read it from production and re-test before applying.'; end if;

  -- audit_logs, as read on 9 Oct 2026.
  select string_agg(a.attname || ' ' || format_type(a.atttypid, a.atttypmod) || case when a.attnotnull then ' not null' else '' end,
                    '|' order by a.attname) into v
    from pg_attribute a
   where a.attrelid = 'public.audit_logs'::regclass and a.attnum > 0 and not a.attisdropped
     and a.attname in ('table_name', 'record_id', 'action', 'old_data', 'new_data', 'changed_by', 'actor_role', 'module');
  if v is distinct from c_cols then
    raise exception '431: public.audit_logs is not shaped as read on 9 Oct 2026 (%)', v; end if;

  -- The new functions: missing, or already this version.
  for r in select * from (values
    ('audit_module(text,text)', c_module_def, c_module_after),
    ('trg_audit_logs_fill_module()', c_fill_def, c_fill_after)) x(fn, def, after_md5)
  loop
    if md5(r.def) <> r.after_md5 then
      raise exception '431: the text of public.% is not the tested one (md5 %)', r.fn, md5(r.def); end if;
    if to_regprocedure('public.' || r.fn) is not null then
      if md5(pg_get_functiondef(to_regprocedure('public.' || r.fn))) <> r.after_md5 then
        raise exception '431: public.% exists and is not this migration''s version', r.fn; end if;
      raise notice '431: public.% is already this version; left alone', r.fn;
    else
      v_fns := v_fns || r.fn;
      v_defs := v_defs || r.def;
    end if;
  end loop;

  -- The changed functions: production's version, or already this one.
  for r in select * from (values
    ('write_audit(text,uuid,text,jsonb,jsonb)', '19cd6b07bdbb6c73c26fb8aa83d2463e', c_wa_after, c_wa_def, null::text[]),
    (c_page_sig, '1b9054e6e243a81e640f0a2a4b18202e', c_page_after, null::text,
     array[[c_page_a1, c_page_r1], [c_page_a2, c_page_r2], [c_page_a3, c_page_r3]])
  ) x(fn, before_md5, after_md5, whole, edits)
  loop
    if to_regprocedure('public.' || r.fn) is null then
      raise exception '431: public.% is missing', r.fn; end if;
    d := pg_get_functiondef(to_regprocedure('public.' || r.fn));
    v := md5(d);
    if v = r.after_md5 then
      raise notice '431: public.% is already this version; left alone', r.fn;
      continue;
    elsif v <> r.before_md5 then
      raise exception '431: public.% is not the version this was tested against (md5 %). Re-read it from production and re-test before applying.', r.fn, v;
    end if;
    if r.edits is null then
      d := r.whole;
    else
      for k in 1 .. array_length(r.edits, 1) loop
        n := (length(d) - length(replace(d, r.edits[k][1], ''))) / length(r.edits[k][1]);
        if n <> 1 then
          raise exception '431: anchor % of public.% was found % times, not once', k, r.fn, n; end if;
        d := replace(d, r.edits[k][1], r.edits[k][2]);
      end loop;
    end if;
    if md5(d) <> r.after_md5 then
      raise exception '431: the text built for public.% is not the tested one (md5 %)', r.fn, md5(d); end if;
    v_fns := v_fns || r.fn;
    v_defs := v_defs || d;
  end loop;

  -- No other function takes any of these names (the API picks an overload by name).
  select string_agg(p.oid::regprocedure::text, ', ') into v_bad from pg_proc p
   where p.pronamespace = 'public'::regnamespace
     and p.proname in ('audit_module', 'trg_audit_logs_fill_module', 'write_audit', 'audit_log_page')
     and p.oid::regprocedure::text <> all (c_changed || array['audit_module(text,text)', 'trg_audit_logs_fill_module()']);
  if v_bad is not null then
    raise exception '431: another function takes one of these names: %', v_bad; end if;

  -- The trigger: missing, or already exactly this one.
  v_trigger_new := not exists (select 1 from pg_trigger t where t.tgrelid = 'public.audit_logs'::regclass
                                  and t.tgname = 'audit_logs_fill_module');
  if not v_trigger_new
     and (select pg_get_triggerdef(t.oid) from pg_trigger t
           where t.tgrelid = 'public.audit_logs'::regclass and t.tgname = 'audit_logs_fill_module') is distinct from c_trigger then
    raise exception '431: a trigger audit_logs_fill_module exists on public.audit_logs and is not this migration''s'; end if;

  -- The grants of the changed functions, to compare after.
  select array_agg(p.oid::regprocedure::text || '=' || coalesce(p.proacl::text, '') order by p.oid::regprocedure::text)
    into v_acl
    from pg_proc p
   where p.pronamespace = 'public'::regnamespace and p.oid::regprocedure::text = any (c_changed);

  -- ── Install ───────────────────────────────────────────────────────────────
  -- audit_module first: write_audit's SQL body and the patched page name it.
  for i in 1 .. coalesce(array_length(v_fns, 1), 0) loop
    execute v_defs[i];
  end loop;
  -- The new functions are internal: other server functions and the trigger
  -- reach them as the owner; no client role may call them.
  revoke all on function public.audit_module(text,text) from public, anon, authenticated;
  grant execute on function public.audit_module(text,text) to service_role;
  revoke all on function public.trg_audit_logs_fill_module() from public, anon, authenticated;
  grant execute on function public.trg_audit_logs_fill_module() to service_role;
  if v_trigger_new then
    create trigger audit_logs_fill_module
      before insert on public.audit_logs
      for each row when (new.module is null)
      execute function public.trg_audit_logs_fill_module();
  end if;

  -- ── Installed exactly as tested ──────────────────────────────────────────
  for r in select * from (values
    ('audit_module(text,text)', c_module_after),
    ('trg_audit_logs_fill_module()', c_fill_after),
    ('write_audit(text,uuid,text,jsonb,jsonb)', c_wa_after),
    (c_page_sig, c_page_after)) x(fn, after_md5)
  loop
    v := md5(pg_get_functiondef(to_regprocedure('public.' || r.fn)));
    if v <> r.after_md5 then
      v_bad := concat_ws('; ', v_bad, r.fn || ' ' || v); end if;
  end loop;
  if v_bad is not null then
    raise exception '431: installed with md5s other than the tested ones: %', v_bad; end if;
  if (select pg_get_triggerdef(t.oid) || ' ' || t.tgenabled::text from pg_trigger t
       where t.tgrelid = 'public.audit_logs'::regclass and t.tgname = 'audit_logs_fill_module')
     is distinct from c_trigger || ' O' then
    raise exception '431: the trigger audit_logs_fill_module is not as tested, or not enabled'; end if;
  if (select array_agg(p.oid::regprocedure::text || '=' || coalesce(p.proacl::text, '') order by p.oid::regprocedure::text)
        from pg_proc p
       where p.pronamespace = 'public'::regnamespace and p.oid::regprocedure::text = any (c_changed))
     is distinct from v_acl then
    raise exception '431: the grants of the changed functions changed'; end if;
  foreach v in array array['audit_module(text,text)', 'trg_audit_logs_fill_module()',
                           'write_audit(text,uuid,text,jsonb,jsonb)'] loop
    if has_function_privilege('anon', 'public.' || v, 'execute')
       or has_function_privilege('authenticated', 'public.' || v, 'execute')
       or not has_function_privilege('service_role', 'public.' || v, 'execute') then
      raise exception '431: public.% is not the service role''s alone', v; end if;
  end loop;
  if has_function_privilege('anon', 'public.' || c_page_sig, 'execute')
     or not has_function_privilege('authenticated', 'public.' || c_page_sig, 'execute') then
    raise exception '431: audit_log_page is not callable by signed-in logins alone'; end if;

  -- ── Behaviour, inside a block that is always undone ───────────────────────
  -- A made-up Owner (@sig.invalid) and made-up entries carrying a mark;
  -- nothing is printed and no row remains.
  begin
    perform set_config('request.jwt.claims', '', true);
    v_mark := '431chk' || replace(gen_random_uuid()::text, '-', '');
    insert into auth.users (id, email) values (gen_random_uuid(), '431-check-owner-' || gen_random_uuid() || '@sig.invalid')
      returning id into v_owner;
    insert into public.profiles (id, full_name, email, role, is_active)
    select u.id, '431 check owner', u.email, 'owner'::public.user_role, true from auth.users u where u.id = v_owner;

    -- The writers, as server functions call them, for the Owner.
    perform set_config('request.jwt.claims', json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);
    perform public.write_audit('staff_commissions', null, 'check_431_a', null, jsonb_build_object('m', v_mark));
    perform public.write_audit('affiliate_accounts', null, 'check_431_b', null, jsonb_build_object('m', v_mark));
    perform public.write_audit_ex('invoices', null, 'check_431_c', null, jsonb_build_object('m', v_mark), 'commission');
    perform public.write_audit_ex('invoices', null, 'check_431_d', null, jsonb_build_object('m', v_mark));
    perform public.write_audit_ex('affiliate_account_claims', null, 'check_431_e', null, jsonb_build_object('m', v_mark), 'affiliate');
    -- Rule 4: voucher therapy rights under therapy, FOC reasons under
    -- invoices; a voucher entry saved with a module keeps it.
    perform public.write_audit('customer_reward_vouchers', null, 'check_431_j', null, jsonb_build_object('m', v_mark));
    perform public.write_audit('foc_reasons', null, 'check_431_k', null, jsonb_build_object('m', v_mark));
    perform public.write_audit_ex('customer_reward_vouchers', null, 'check_431_l', null, jsonb_build_object('m', v_mark), 'refunds');
    perform set_config('request.jwt.claims', '', true);
    -- Written straight into the table, as some server functions do.
    insert into public.audit_logs (table_name, action, module, new_data)
    values ('profiles', 'check_431_f', null, jsonb_build_object('m', v_mark)),
           ('user_invitations', 'check_431_g', null, jsonb_build_object('m', v_mark)),
           ('invoices', 'check_431_h', 'commission', jsonb_build_object('m', v_mark));
    -- An entry from before this, saved with no module (the trigger off).
    alter table public.audit_logs disable trigger audit_logs_fill_module;
    insert into public.audit_logs (table_name, action, module, new_data)
    values ('profiles', 'check_431_i', null, jsonb_build_object('m', v_mark));
    alter table public.audit_logs enable trigger audit_logs_fill_module;

    select string_agg(a.action || ':' || coalesce(a.module, '-') || ':' || coalesce(a.actor_role, '-'), ',' order by a.action)
      into v_rows from public.audit_logs a where a.new_data ->> 'm' = v_mark;
    if v_rows is distinct from 'check_431_a:commissions:owner,check_431_b:affiliate_accounts:owner,check_431_c:commission:owner,'
                               'check_431_d:invoices:owner,check_431_e:affiliate:owner,check_431_f:users:-,'
                               'check_431_g:users:-,check_431_h:commission:-,check_431_i:-:-,check_431_j:therapy:owner,'
                               'check_431_k:invoices:owner,check_431_l:refunds:owner' then
      raise exception '431: the modules saved are not as tested'; end if;

    -- The Audit Log, signed in as the Owner.
    perform set_config('request.jwt.claims', json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    j := public.audit_log_page(p_text => v_mark, p_with_choices => true);
    if (j ->> 'total')::int <> 12
       or (select string_agg(concat_ws(':', r2 ->> 'action', r2 ->> 'module', r2 ->> 'module_recorded'), ','
                             order by r2 ->> 'action')
             from jsonb_array_elements(j -> 'rows') r2)
          is distinct from 'check_431_a:commissions:true,check_431_b:affiliate_accounts:true,check_431_c:commissions:true,'
                           'check_431_d:invoices:true,check_431_e:affiliate:true,check_431_f:users:true,'
                           'check_431_g:users:true,check_431_h:commissions:true,check_431_i:users:false,'
                           'check_431_j:therapy:true,check_431_k:invoices:true,check_431_l:refunds:true' then
      raise exception '431: the Audit Log does not show the modules as tested'; end if;
    if exists (select 1 from jsonb_array_elements(j -> 'choices' -> 'modules') x where x ->> 'value' = 'commission')
       or not exists (select 1 from jsonb_array_elements(j -> 'choices' -> 'modules') x where x ->> 'value' = 'commissions') then
      raise exception '431: the module filter does not offer one commissions'; end if;
    if (public.audit_log_page(p_module => 'commissions', p_text => v_mark) ->> 'total')::int <> 3
       or (public.audit_log_page(p_module => 'commission', p_text => v_mark) ->> 'total')::int <> 3
       or (public.audit_log_page(p_module => 'users', p_text => v_mark) ->> 'total')::int <> 3
       or (public.audit_log_page(p_module => 'invoices', p_text => v_mark) ->> 'total')::int <> 2
       or (public.audit_log_page(p_module => 'therapy', p_text => v_mark) ->> 'total')::int <> 1
       or (public.audit_log_page(p_module => 'refunds', p_text => v_mark) ->> 'total')::int <> 1 then
      raise exception '431: filtering by module is not as tested'; end if;
    execute 'reset role';
    raise exception using errcode = 'P0431', message = '431: check done, undone';
  exception when sqlstate 'P0431' then null;
  end;
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  if (select t.tgenabled::text from pg_trigger t where t.tgrelid = 'public.audit_logs'::regclass
        and t.tgname = 'audit_logs_fill_module') is distinct from 'O' then
    raise exception '431: the trigger is not enabled after the check'; end if;

  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $mig$;
