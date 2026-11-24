-- 532_changes_made_straight_on_the_tables_are_recorded.sql
--
-- A CHANGE MADE STRAIGHT ON A STORE, A PAYMENT METHOD, A PROMOTION, A STAFF PROFILE OR ANOTHER
-- SETTINGS TABLE IS RECORDED IN THE AUDIT LOG; A MANAGER CHANGES ONLY THEIR OWN STORES AND THEIR
-- IMAGES; A PAYMENT METHOD'S WALLET SETTINGS ARE LOCKED; THE WRITE RULES NO PAGE USES ARE CLOSED
--
--   From the security audit of 17 Nov 2026 (findings M7 and M8).
--   The rules, the relied-on md5s, the BEFORE md5s and the server functions below are those of
--   production at 529 (head 20261119103500, the local copy of 20 Nov 2026), and they are the same
--   with 530 and 531 in. If production differs when this is applied, it refuses and changes
--   nothing.
--   (The number 532 is this file's name and its errors' prefix; if it changes at commit, change it
--   there, in the 532 comments it writes into trg_audit_direct_change(),
--   trg_payment_method_wallet_locked(), soft_delete_store, restore_store and
--   set_store_policy_text (and so their md5s, also in scripts/audit-log/undo-532.sql and in the
--   suites that know them), and in the name and path of its suite.)
--
-- WHAT WAS WRONG
--
--   A signed-in Owner or Manager (and an Inventory Manager for products) could write 23 tables
--   straight through the table API, under their row rules, and nothing was recorded (M7):
--     1. Twelve tables the pages write directly: stores (PayNow UEN, bank account, QR addresses,
--        GST), warehouses, payment methods, promotions with their choice groups, choice options
--        and items, special products, survey links, brands, categories and suppliers. Vouchers and
--        their store prices have been recorded since 423.
--     2. Eleven tables the pages change only through server functions that write their own audit
--        entry still had write rules no page uses: a signed health survey (any column), the
--        symptom list, products and their category and supplier links, special products (insert
--        and delete), promotion items (insert and update), and the prices and voucher stock per
--        store. Through those rules a change skipped the function, its checks and its entry. Nine
--        more rules no page uses let a row be deleted outright, or a promotion's choices edited in
--        place: a promotion deleted outright took its items, choices and prices with it.
--     3. Any Manager could change any store's payment details and add stores, whatever stores they
--        work at, and could overwrite any store's PayNow, GrabPay or Atome QR image in place (the
--        files of the public bucket 'store-assets', which the till shows the customer), the store's
--        row untouched; and any Owner or Manager could flip a payment method's "wallet credit"
--        settings, which decide which past payments count as sales in every report and in Xero.
--   And a change to a staff profile (a role, a name, a phone) left no entry at all (M8): only a
--   login switched off or on left one (412).
--
-- THE RULES (the user, 20 Nov 2026)
--
--   * Stores: "Managers: own stores only". An Owner changes every store; a Manager only the stores
--     they work at (user_store_assignments); adding a store is an Owner's. Every change is
--     recorded. Warehouses stay as they are (Managers company-wide), recorded.
--   * Payment methods: "Lock it". No login sets or changes a payment method's wallet settings.
--   * M8: "Yes, with M7".
--
-- WHAT THIS DOES
--
--   * trg_audit_direct_change(), new, internal (the service role's alone, as 423's
--     trg_audit_voucher_change), modelled on 423: an insert records the new row, a delete the old
--     row, an update only the columns that changed, before and after, and nothing when only
--     updated_at or updated_by changed. The action is <noun>_created, _updated, _deleted
--     (deleted_at set), _restored (deleted_at cleared) or _removed (the row deleted), with the
--     table's noun: store, warehouse, payment_method, promotion, promotion_choice_group,
--     promotion_choice_option, promotion_item, special_product, survey_link, brand, category,
--     supplier. The entry is filed under the row, except a promotion item or choice group (under
--     its promotion) and a choice option (under its group's promotion); the row's own id stays in
--     the data (row_id on an update). Its store: the store itself for stores (none when a store
--     row is deleted outright: the audit log's store must exist), the link's store for survey
--     links. Its module: 'catalogue' for special products and promotion items, 'promotions' for
--     promotions and their choice groups and options, as their existing entries have it; for the
--     rest none is given, and audit_module() files it under the table's name as before. The actor
--     is the signed-in login's profile and role, as in 423; with no staff login (the secret key)
--     the role is the API's own ('service_role'), read from the session's role.
--     A staff profile (M8): staff_role_changed when the role changed, else staff_profile_updated,
--     filed under the profile ('users', from the table), with the columns changed, before and
--     after; staff_profile_created with the new row and staff_profile_removed with the old one
--     when a profile is made or removed outright (only the secret key can: no rule lets a login,
--     and the invitation functions run as their owner and record their own). When a staff login
--     switches a login off or on, and nothing else, and 412's staff_login_sync will record the
--     switch with that actor (a login switched off that it has not blocked yet:
--     staff_login_blocked; a login switched on that it had blocked: staff_login_unblocked), this
--     records nothing, so one click gives one entry; a switch 412 does not record (a login
--     switched on that it never blocked) is recorded here, and so is a switch by the secret key
--     (412's entry then names nobody; this one says service_role), beside 412's. This reads
--     staff_login_blocks before 412's trigger runs: AFTER triggers run by name, and
--     audit_direct_change comes before staff_login_follows_profile.
--   * A trigger audit_direct_change on each of the twelve tables and on profiles, AFTER INSERT OR
--     UPDATE OR DELETE, FOR EACH ROW, WHEN the writer is the table API's own role
--     (current_user anon, authenticated or service_role: a signed-in login, or the secret key). A
--     change made inside a server function (SECURITY DEFINER, run as its owner) is left to that
--     function's own entry (soft_delete_store, restore_store, add_promotion_item,
--     upsert_special_product_from_product, invite_user_accept and the rest), and a cascade (run as
--     the table's owner) to the entry of the row it follows, so one change gives one entry. A
--     change in the SQL editor (postgres) is not recorded.
--   * Stores: the rule "update stores" lets an Owner change every store and a Manager only the
--     stores they work at (current_user_store_ids(), as 520's read rules use it); "insert stores"
--     an Owner only. The Owner test is current_user_role() = 'owner' (is_owner() is not open to
--     signed-in logins). An Admin changes none, as before. soft_delete_store and restore_store
--     (Delete and Restore on the Stores page) refuse a Manager on a store they do not work at
--     (42501), after the store is found; the secret key (no role) passes as before; the rest of
--     their text is as before. set_store_policy_text (the secret key's alone, no page calls it)
--     records its change (store_updated, the policy text before and after), which the trigger
--     leaves to it.
--   * The store images (storage.objects, bucket 'store-assets', '<store id>/<file>'): "store-assets
--     write" lets an Owner add a file into any store's folder and a Manager into their own stores'
--     (survey_attachment_store(name), the store the first folder names); "store-assets update" and
--     "store-assets delete" are dropped (no page replaces or removes a file: Remove on the Stores
--     page clears the URL; the update rule served only an upsert). A file is then never replaced
--     or removed by a login, so an image changes only through the store's row (its URL), which is
--     recorded. "store-assets read" (public) is not changed.
--   * Payment methods: trg_payment_method_wallet_locked(), new, and a trigger
--     payment_method_wallet_locked, BEFORE INSERT OR UPDATE, WHEN the writer is the table API's own
--     role: a new payment method must leave is_wallet_credit, wallet_category, wallet_source and
--     is_system at their defaults (false, none, none, false), and a change must leave them as they
--     are, or it is refused: "A payment method's wallet settings cannot be changed here." (42501).
--     Adding, renaming and switching on and off are as before (the page sends only the name, the
--     active flag and deleted_at), and recorded. trg_protect_system_payment_methods is not changed.
--   * The 33 write rules no page uses are dropped, each only as tested (command, role, test):
--       health_surveys          "update surveys"
--       health_symptom_options  "insert symptom options", "update symptom options",
--                               "delete symptom options"
--       product_categories      "product_categories write"   (its "product_categories read" stays)
--       product_suppliers       "product_suppliers write"    (its "product_suppliers read" stays)
--       products                "insert products", "update products"
--       promotion_items         "insert promotion items", "update promotion items"
--                               ("delete promotion items" stays: the Promotions page's Remove)
--       special_products        "insert special products", "delete special products"
--                               ("update special products" stays: the Special page's Delete)
--       store_product_prices    "insert store prices", "update store prices", "delete store prices"
--       promotion_store_prices  "insert promotion prices", "update promotion prices",
--                               "delete promotion prices"
--       voucher_store_prices    "insert voucher prices", "update voucher prices",
--                               "delete voucher prices"
--       voucher_store_stock     "insert voucher stock", "update voucher stock",
--                               "delete voucher stock"
--       brands, categories, suppliers  "brands delete", "categories delete", "suppliers delete"
--       payment_methods         "delete payment methods"
--       promotions              "delete promotions"
--       survey_links            "delete survey links"
--       vouchers                "delete vouchers"
--       promotion_choice_groups "update choice groups"      ("delete choice groups" stays)
--       promotion_choice_options "update choice options"    ("delete choice options" stays)
--     The pages save these through server functions (save_product, set_product_prices,
--     set_promotion_prices, set_promotion_price_all_stores, set_voucher_prices,
--     set_voucher_price_all_stores, voucher_stock_in, update_survey_particulars_v2,
--     add_promotion_item, upsert_special_product_from_product, set_special_product_consignment,
--     soft_delete_voucher), or delete by switching off (deleted_at) and choices by deleting one and
--     adding another: each function is checked here to be there, SECURITY DEFINER and open to
--     signed-in logins, so none needs the rules. Nothing in src/, supabase/functions/ or scripts/
--     writes these tables straight as a login (searched 20 Nov 2026; scripts/phase4_acceptance.mjs
--     uses the secret key, which no row rule binds).
--
-- WHAT THIS LEAVES ALONE
--
--   * Who may write the other eleven watched tables: as before (an Owner or Manager, for every
--     store). Warehouses included.
--   * Who may change a profile: the rule "update profiles" and guard_profile_privileges (407, 512).
--   * A profile removed with its login (an auth.users row deleted: the database cascades it, as the
--     table's owner) is not recorded here, as any cascade.
--   * vouchers and voucher_store_prices: recorded by 423's trigger, unchanged.
--   * The read rules of every table, the grants of every table, every function but the five named
--     above, the files already in the bucket, and every row already written; no data changes.
--
-- UNDO
--
--   First put back the Stores page and src/lib/storeAssets.ts of before 532. Then
--   scripts/audit-log/undo-532.sql (it refuses unless the new functions, the triggers, the store
--   and store-assets rules and the three store functions are 532's, no other trigger uses the new
--   functions, and none of the dropped rules is there again): the 33 rules and the two store-assets
--   rules are made again and the store rules and functions put back, exactly as they were, and
--   the fourteen triggers and the two functions are dropped. The audit rows stay. A later
--   migration changing any of the five functions must pin 532's md5.
--
-- NO SELF-TEST INSIDE; the suite is scripts/audit-log/tests/direct-changes-recorded-532.sql.
--
-- One transaction with its history row, by the usual wrapper; nothing else is written.

do $mig$
declare
  -- ── Relied on, as tested: the actor's role, the stores a login works at, the module an entry
  --    is filed under, 423's voucher trigger (vouchers stay with it), and 412's login sync, whose
  --    entries for a switched login this does not repeat.
  c_relied constant text[] := array[
    'current_user_role()',
    'is_owner_or_manager()',
    'current_user_store_ids()',
    'audit_module(text,text)',
    'trg_audit_logs_fill_module()',
    'trg_audit_voucher_change()',
    'staff_login_sync(uuid)',
    'trg_staff_login_follows_profile()',
    'survey_attachment_store(text)'];
  c_relied_md5 constant text[] := array[
    '519b0a33a3548f970c5d585b6e76a389',
    'a98e50f1b6d3fa1e6c62cf52a8073cc8',
    '54191b973c31654b903d48bea01ce533',
    'daf0c43e9e9578e78048b2f6d7cba57e',
    '417a84925a3e465bcc9f11f7c13bb673',
    '59793e632d567d28a5917066a187411d',
    '9259111deccca8c66e95469acfdd250f',
    'a3a60fef98d7755b7104a5d96c4e38f8',
    '58f7d30040f104d240b40ec3e9d9567f'];
  -- The helpers the new store rules (stores, store-assets) call as the signed-in login: each must
  -- be open to signed-in logins (is_owner() is not, so the Owner test is current_user_role()).
  c_rule_helpers constant text[] := array[
    'current_user_role()', 'is_owner_or_manager()', 'current_user_store_ids()', 'survey_attachment_store(text)'];
  -- 412's trigger on profiles, which must run after audit_direct_change (by name).
  c_412_trg constant text := 'CREATE TRIGGER staff_login_follows_profile AFTER INSERT OR UPDATE OF is_active, deleted_at, invitation_status ON public.profiles FOR EACH ROW EXECUTE FUNCTION trg_staff_login_follows_profile()';
  -- ── The pages' server functions for the tables whose write rules are dropped: each must be
  --    there, SECURITY DEFINER and executable by signed-in logins (their texts may change later).
  c_route constant text[] := array[
    'save_product(uuid,jsonb,uuid[],uuid[])',
    'set_product_prices(uuid,uuid,numeric,numeric,text)',
    'set_promotion_prices(uuid,uuid,numeric,numeric,boolean)',
    'set_promotion_price_all_stores(uuid,numeric,boolean)',
    'set_voucher_prices(uuid,uuid,numeric,numeric,boolean)',
    'set_voucher_price_all_stores(uuid,numeric,boolean)',
    'voucher_stock_in(uuid,uuid,integer,text,uuid)',
    'update_survey_particulars_v2(uuid,jsonb,text)',
    'add_promotion_item(uuid,promotion_item_type,uuid,uuid,uuid,text,integer,text,uuid,uuid)',
    'upsert_special_product_from_product(uuid,uuid,numeric,numeric,numeric,numeric,numeric,numeric,text,boolean)',
    'set_special_product_consignment(uuid,boolean)',
    'soft_delete_voucher(uuid,text,boolean)'];

  -- ── New: the audit of a change made straight on a table ─────────────────────────────────────
  c_fn_sig constant text[] := array['trg_audit_direct_change()', 'trg_payment_method_wallet_locked()'];
  c_fn_md5 constant text[] := array['b2ac8670825d1daf73a27c74e64bd66a', '3b6d9b8590d7bdec9df746cff62024f5'];
  c_fn_acl constant text := 'postgres=X/postgres,service_role=X/postgres';
  c_fn_def constant text[] := array[
$def$CREATE OR REPLACE FUNCTION public.trg_audit_direct_change()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_row jsonb; v_prev jsonb; v_old jsonb; v_new jsonb; v_noun text; v_action text;
  v_record uuid; v_store uuid; v_module text; v_blocked boolean;
begin
  -- 532 (security audit of 17 Nov 2026, M7 and M8): a change made straight on one of these
  -- tables through the table API goes in the audit log, as 423 records vouchers. The triggers call
  -- this only when the writer is the API's own role (a signed-in login, or the secret key); a
  -- change made inside a server function is left to that function's own entry, and a cascade to
  -- the entry of the row it follows. An insert records the new row, a delete the old one, an
  -- update only the columns that changed, before and after, and nothing when only updated_at or
  -- updated_by changed. The actor is the signed-in login's profile and role; with no staff login
  -- (the secret key) the role is the API's own ('service_role'), read from the session's role,
  -- which this function's owner rights do not change.
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

  -- A staff profile (M8): made or removed outright (only the secret key can; the invitation
  -- functions run as their owner and record their own), or changed. A login switched off or on
  -- by a staff login, and nothing else, is recorded by 412's staff_login_sync with that actor when
  -- it blocks the login or lifts its block; that trigger runs after this one, so the block read
  -- here is the one it will find. Switched by the secret key, 412's entry names nobody, so this
  -- one is written too.
  if tg_table_name = 'profiles' then
    if tg_op = 'UPDATE' and v_old ?& array['is_active'] and (select count(*) from jsonb_object_keys(v_old)) = 1
       and v_row ->> 'deleted_at' is null and coalesce(v_row ->> 'invitation_status', 'accepted') = 'accepted'
       and public.current_user_role() is not null then
      v_blocked := exists (select 1 from public.staff_login_blocks b where b.user_id = (v_row ->> 'id')::uuid);
      if (v_row ->> 'is_active')::boolean = v_blocked then
        return null;
      end if;
    end if;
    v_action := case tg_op when 'INSERT' then 'staff_profile_created'
                           when 'DELETE' then 'staff_profile_removed'
                           else case when v_old ? 'role' then 'staff_role_changed' else 'staff_profile_updated' end end;
    insert into public.audit_logs
      (table_name, record_id, action, old_data, new_data, changed_by, actor_role)
    values (tg_table_name, (v_row ->> 'id')::uuid, v_action, v_old, v_new,
            (select p.id from public.profiles p where p.id = auth.uid()),
            coalesce(public.current_user_role()::text, nullif(current_setting('role', true), 'none')));
    return null;
  end if;

  -- The table's noun, the record the entry is filed under, its store and its module.
  v_noun := case tg_table_name
    when 'stores' then 'store'
    when 'warehouses' then 'warehouse'
    when 'payment_methods' then 'payment_method'
    when 'promotions' then 'promotion'
    when 'promotion_choice_groups' then 'promotion_choice_group'
    when 'promotion_choice_options' then 'promotion_choice_option'
    when 'promotion_items' then 'promotion_item'
    when 'special_products' then 'special_product'
    when 'survey_links' then 'survey_link'
    when 'brands' then 'brand'
    when 'categories' then 'category'
    when 'suppliers' then 'supplier'
    else tg_table_name end;
  if tg_table_name in ('promotion_items', 'promotion_choice_groups') then
    v_record := (v_row ->> 'promotion_id')::uuid;
  elsif tg_table_name = 'promotion_choice_options' then
    select g.promotion_id into v_record
      from public.promotion_choice_groups g where g.id = (v_row ->> 'group_id')::uuid;
  else
    v_record := (v_row ->> 'id')::uuid;
  end if;
  if tg_op = 'UPDATE' and tg_table_name in ('promotion_items', 'promotion_choice_groups', 'promotion_choice_options') then
    v_new := v_new || jsonb_build_object('row_id', v_row -> 'id');
  end if;
  if tg_table_name = 'stores' and tg_op <> 'DELETE' then
    -- A store deleted outright has no row left for the entry's store to point to.
    v_store := (v_row ->> 'id')::uuid;
  elsif tg_table_name = 'survey_links' then
    v_store := (v_row ->> 'store_id')::uuid;
  end if;
  v_module := case
    when tg_table_name in ('special_products', 'promotion_items') then 'catalogue'
    when tg_table_name in ('promotions', 'promotion_choice_groups', 'promotion_choice_options') then 'promotions'
    end;

  if tg_op = 'INSERT' then
    v_action := v_noun || '_created';
  elsif tg_op = 'DELETE' then
    v_action := v_noun || '_removed';
  elsif v_prev ->> 'deleted_at' is null and v_row ->> 'deleted_at' is not null then
    v_action := v_noun || '_deleted';
  elsif v_prev ->> 'deleted_at' is not null and v_row ->> 'deleted_at' is null then
    v_action := v_noun || '_restored';
  else
    v_action := v_noun || '_updated';
  end if;

  insert into public.audit_logs
    (table_name, record_id, action, old_data, new_data, changed_by, actor_role, module, store_id)
  values (tg_table_name, v_record, v_action, v_old, v_new,
          (select p.id from public.profiles p where p.id = auth.uid()),
          coalesce(public.current_user_role()::text, nullif(current_setting('role', true), 'none')), v_module, v_store);
  return null;
end
$function$
$def$,
$def$CREATE OR REPLACE FUNCTION public.trg_payment_method_wallet_locked()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
begin
  -- 532 (security audit of 17 Nov 2026, M7; the user, 20 Nov 2026: "Lock it"): a payment
  -- method's wallet settings decide which payments count as sales in every report and in Xero.
  -- Through the table API (a signed-in login, or the secret key: the trigger's WHEN) a new
  -- payment method leaves them at their defaults and a change leaves them as they are. The
  -- built-in wallet methods are made by migrations.
  if tg_op = 'INSERT' then
    if new.is_wallet_credit is distinct from false or new.wallet_category is not null
       or new.wallet_source is not null or new.is_system is distinct from false then
      raise exception 'A payment method''s wallet settings cannot be changed here.' using errcode = '42501';
    end if;
  elsif new.is_wallet_credit is distinct from old.is_wallet_credit
        or new.wallet_category is distinct from old.wallet_category
        or new.wallet_source is distinct from old.wallet_source
        or new.is_system is distinct from old.is_system then
    raise exception 'A payment method''s wallet settings cannot be changed here.' using errcode = '42501';
  end if;
  return new;
end
$function$
$def$];

  -- ── The triggers, as pg_get_triggerdef prints them ──────────────────────────────────────────
  c_trg_name constant text := 'audit_direct_change';
  c_trg_table constant text[] := array[
    'stores', 'warehouses', 'payment_methods',
    'promotions', 'promotion_choice_groups', 'promotion_choice_options', 'promotion_items',
    'special_products', 'survey_links',
    'brands', 'categories', 'suppliers',
    'profiles'];
  -- The events each watches: every change.
  c_trg_ops constant text[] := array[
    'INSERT OR DELETE OR UPDATE', 'INSERT OR DELETE OR UPDATE', 'INSERT OR DELETE OR UPDATE',
    'INSERT OR DELETE OR UPDATE', 'INSERT OR DELETE OR UPDATE', 'INSERT OR DELETE OR UPDATE', 'INSERT OR DELETE OR UPDATE',
    'INSERT OR DELETE OR UPDATE', 'INSERT OR DELETE OR UPDATE',
    'INSERT OR DELETE OR UPDATE', 'INSERT OR DELETE OR UPDATE', 'INSERT OR DELETE OR UPDATE',
    'INSERT OR DELETE OR UPDATE'];
  c_trg_def constant text := 'CREATE TRIGGER audit_direct_change AFTER %s ON public.%s FOR EACH ROW WHEN ((CURRENT_USER = ANY (ARRAY[''anon''::name, ''authenticated''::name, ''service_role''::name]))) EXECUTE FUNCTION trg_audit_direct_change()';
  c_pm_trg_def constant text := 'CREATE TRIGGER payment_method_wallet_locked BEFORE INSERT OR UPDATE ON public.payment_methods FOR EACH ROW WHEN ((CURRENT_USER = ANY (ARRAY[''anon''::name, ''authenticated''::name, ''service_role''::name]))) EXECUTE FUNCTION trg_payment_method_wallet_locked()';
  -- The columns the functions read (name type, and for payment methods' wallet settings their
  -- defaults), as read on 20 Nov 2026. Other columns may come and go: the audit copies whole rows.
  c_cols constant text[] := array[
    'audit_logs:action text|actor_role text|changed_by uuid|module text|new_data jsonb|old_data jsonb|record_id uuid|store_id uuid|table_name text',
    'promotion_choice_groups:id uuid|promotion_id uuid',
    'promotion_choice_options:group_id uuid|id uuid',
    'promotion_items:id uuid|promotion_id uuid',
    'stores:id uuid',
    'survey_links:id uuid|store_id uuid',
    'profiles:deleted_at timestamp with time zone|id uuid|invitation_status text|is_active boolean|role user_role',
    'staff_login_blocks:user_id uuid',
    'payment_methods:is_system boolean|is_wallet_credit boolean|wallet_category text|wallet_source text'];
  c_pm_defaults constant text := 'is_system=false|is_wallet_credit=false|wallet_category=|wallet_source=';

  -- ── Stores: a Manager's own stores; adding one is an Owner's ────────────────────────────────
  c_st_om constant text := '( SELECT is_owner_or_manager() AS is_owner_or_manager)';
  c_st_upd_src constant text :=
    '(select public.current_user_role()) = ''owner''::public.user_role '
    || 'or ((select public.is_owner_or_manager()) and id = any ((select public.current_user_store_ids())::uuid[]))';
  c_st_ins_src constant text := '(select public.current_user_role()) = ''owner''::public.user_role';
  c_st_upd_after constant text :=
    '((( SELECT current_user_role() AS current_user_role) = ''owner''::user_role) OR (( SELECT is_owner_or_manager() AS is_owner_or_manager) AND (id = ANY (( SELECT current_user_store_ids() AS current_user_store_ids)::uuid[]))))';
  c_st_ins_after constant text := '(( SELECT current_user_role() AS current_user_role) = ''owner''::user_role)';
  -- Delete and Restore on the Stores page: patched after the store is found. And
  -- set_store_policy_text (the secret key's alone; no page calls it): it now records its change,
  -- which the audit trigger leaves to it (it runs as its owner).
  c_sig constant text[] := array['soft_delete_store(uuid)', 'restore_store(uuid)', 'set_store_policy_text(uuid,text)'];
  c_before constant text[] := array['61020273511f69bac2dd86d530d38d2e', 'a29cb102c967cc5a2939a1a334e86b07', 'b7793f4b636e7cccf96b7e80e03cfb03'];
  c_after constant text[] := array['3bf8f7b89f34cffae2d46c97a8462c07', '54c3b5e1275429b73b6e6506a2b31ddd', '807d49611ca6fb2896cde9ee9413def9'];
  c_acl constant text[] := array[
    'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres',
    'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres',
    'postgres=X/postgres,service_role=X/postgres'];
  c_anchor constant text[] := array[
$a$  if not found then raise exception 'Store not found'; end if;
$a$,
$a$  if not found then raise exception 'Store not found'; end if;
$a$,
$a$  update public.stores set policy_text = nullif(trim(coalesce(p_text,'')),'') where id = p_store_id;
$a$];
  c_new constant text[] := array[
$n$  if not found then raise exception 'Store not found'; end if;
  -- 532 (security audit of 17 Nov 2026, M7; the user, 20 Nov 2026: "Managers: own stores
  -- only"): an Owner deletes any store, a Manager only a store they work at.
  if v_role = 'manager' and not (p_store_id = any (public.current_user_store_ids())) then
    raise exception 'A Manager can delete only the stores they work at.' using errcode = '42501'; end if;
$n$,
$n$  if not found then raise exception 'Store not found'; end if;
  -- 532 (security audit of 17 Nov 2026, M7; the user, 20 Nov 2026: "Managers: own stores
  -- only"): an Owner restores any store, a Manager only a store they work at.
  if v_role = 'manager' and not (p_store_id = any (public.current_user_store_ids())) then
    raise exception 'A Manager can restore only the stores they work at.' using errcode = '42501'; end if;
$n$,
$n$  -- 532 (security audit of 17 Nov 2026, M7: "every change is recorded"): the policy text before
  -- and after, as a change made straight on the table is recorded (trg_audit_direct_change).
  with o as (select s.id, s.policy_text from public.stores s where s.id = p_store_id for update),
       u as (update public.stores s set policy_text = nullif(trim(coalesce(p_text,'')),'') from o
              where s.id = o.id returning s.id, o.policy_text as old_text, s.policy_text as new_text)
  insert into public.audit_logs (table_name, record_id, action, old_data, new_data, changed_by, actor_role, store_id)
  select 'stores', u.id, 'store_updated', jsonb_build_object('policy_text', u.old_text),
         jsonb_build_object('policy_text', u.new_text), (select p.id from public.profiles p where p.id = auth.uid()),
         coalesce(public.current_user_role()::text, nullif(current_setting('role', true), 'none')), u.id
    from u where u.old_text is distinct from u.new_text;
$n$];
  -- ── The store images (the PayNow, GrabPay and Atome QR codes the till shows, and the logos):
  --    files in the public bucket 'store-assets' at '<store id>/<file>'. A file is added by an
  --    Owner (any store) or a Manager (their own stores), into that store's folder, and never
  --    replaced or removed by a login: an image changes only through the store's row (its URL),
  --    which is recorded.
  c_sa_pol constant text[] := array['store-assets read', 'store-assets write', 'store-assets update', 'store-assets delete'];
  c_sa_cmd constant text[] := array['r', 'a', 'w', 'd'];
  c_sa_roles constant text[] := array['{-}', '{authenticated}', '{authenticated}', '{authenticated}'];
  c_sa_qual constant text[] := array[
    '(bucket_id = ''store-assets''::text)',
    null,
    '((bucket_id = ''store-assets''::text) AND ( SELECT is_owner_or_manager() AS is_owner_or_manager))',
    '((bucket_id = ''store-assets''::text) AND ( SELECT is_owner_or_manager() AS is_owner_or_manager))'];
  c_sa_check constant text[] := array[
    null,
    '((bucket_id = ''store-assets''::text) AND ( SELECT is_owner_or_manager() AS is_owner_or_manager))',
    null,
    null];
  c_sa_write_src constant text :=
    'bucket_id = ''store-assets'' and (select public.is_owner_or_manager()) '
    || 'and public.survey_attachment_store(name) = any ((select public.current_user_store_ids())::uuid[])';
  c_sa_write_after constant text :=
    '((bucket_id = ''store-assets''::text) AND ( SELECT is_owner_or_manager() AS is_owner_or_manager) AND (survey_attachment_store(name) = ANY (( SELECT current_user_store_ids() AS current_user_store_ids)::uuid[])))';

  -- ── The write rules dropped, each as tested (all permissive, for authenticated) ─────────────
  c_om constant text := '( SELECT is_owner_or_manager() AS is_owner_or_manager)';
  c_ep constant text := '( SELECT can_edit_products() AS can_edit_products)';
  c_pol_table constant text[] := array[
    'health_surveys',
    'health_symptom_options', 'health_symptom_options', 'health_symptom_options',
    'product_categories', 'product_suppliers',
    'products', 'products',
    'promotion_items', 'promotion_items',
    'special_products', 'special_products',
    'store_product_prices', 'store_product_prices', 'store_product_prices',
    'promotion_store_prices', 'promotion_store_prices', 'promotion_store_prices',
    'voucher_store_prices', 'voucher_store_prices', 'voucher_store_prices',
    'voucher_store_stock', 'voucher_store_stock', 'voucher_store_stock',
    -- The hard deletes and the choice edits no page makes (the pages switch these off and back on,
    -- or delete a choice and add another); a promotion deleted outright takes its items, choices
    -- and prices with it, unrecorded.
    'brands', 'categories', 'suppliers', 'payment_methods', 'promotions', 'survey_links', 'vouchers',
    'promotion_choice_groups', 'promotion_choice_options'];
  c_pol_name constant text[] := array[
    'update surveys',
    'insert symptom options', 'update symptom options', 'delete symptom options',
    'product_categories write', 'product_suppliers write',
    'insert products', 'update products',
    'insert promotion items', 'update promotion items',
    'insert special products', 'delete special products',
    'insert store prices', 'update store prices', 'delete store prices',
    'insert promotion prices', 'update promotion prices', 'delete promotion prices',
    'insert voucher prices', 'update voucher prices', 'delete voucher prices',
    'insert voucher stock', 'update voucher stock', 'delete voucher stock',
    'brands delete', 'categories delete', 'suppliers delete', 'delete payment methods', 'delete promotions',
    'delete survey links', 'delete vouchers',
    'update choice groups', 'update choice options'];
  -- pg_policy.polcmd: a insert, w update, d delete, * all.
  c_pol_cmd constant text[] := array[
    'w',
    'a', 'w', 'd',
    '*', '*',
    'a', 'w',
    'a', 'w',
    'a', 'd',
    'a', 'w', 'd',
    'a', 'w', 'd',
    'a', 'w', 'd',
    'a', 'w', 'd',
    'd', 'd', 'd', 'd', 'd', 'd', 'd',
    'w', 'w'];
  -- Their tests (USING, WITH CHECK) as pg_get_expr prints them, null where there is none.
  c_pol_qual constant text[] := array[
    c_om,
    null, c_om, c_om,
    c_ep, c_ep,
    null, c_ep,
    null, c_om,
    null, c_om,
    null, c_om, c_om,
    null, c_om, c_om,
    null, c_om, c_om,
    null, c_om, c_om,
    c_om, c_om, c_om, c_om, c_om, c_om, c_om,
    c_om, c_om];
  c_pol_check constant text[] := array[
    c_om,
    c_om, c_om, null,
    c_ep, c_ep,
    c_ep, c_ep,
    c_om, c_om,
    c_om, null,
    c_om, c_om, null,
    c_om, c_om, null,
    c_om, c_om, null,
    c_om, c_om, null,
    null, null, null, null, null, null, null,
    c_om, c_om];
  -- ── The rules the pages still use on those tables: they stay, and must be there ─────────────
  c_keep_table constant text[] := array['product_categories', 'product_suppliers', 'promotion_items', 'special_products',
                                         'promotion_choice_groups', 'promotion_choice_options'];
  c_keep_name constant text[] := array['product_categories read', 'product_suppliers read', 'delete promotion items', 'update special products',
                                        'delete choice groups', 'delete choice options'];
  c_keep_cmd constant text[] := array['r', 'r', 'd', 'w', 'd', 'd'];

  v_path text := current_setting('search_path');
  v_lock text := current_setting('lock_timeout');
  v_bad text := '';
  v_def text[] := array_fill(null::text, array[3]);
  d text; i int; n int; v_tab text; v_want text; v_have text;
begin
  -- Definitions are read and compared with public alone on the search path.
  perform set_config('search_path', 'public', true);
  -- A busy table waits 5 seconds at most, then this refuses whole.
  perform set_config('lock_timeout', '5s', true);

  -- 1. Checks: nothing is changed before all of them pass
  -- Already in, or something of the same name there: refused.
  for i in 1 .. cardinality(c_fn_sig) loop
    if to_regprocedure('public.' || c_fn_sig[i]) is not null then
      if position('532 (security audit' in pg_get_functiondef(to_regprocedure('public.' || c_fn_sig[i]))) > 0 then
        raise exception '532 is already in on this database (public.% is there). Nothing was changed.', c_fn_sig[i];
      end if;
      raise exception '532: a function public.% is there, but not 532''s. Re-read it before applying.', c_fn_sig[i];
    end if;
    -- The text of the new function is the tested one.
    if md5(c_fn_def[i]) <> c_fn_md5[i] then
      raise exception '532: the text of public.% in this file is not the tested one (md5 %)', c_fn_sig[i], md5(c_fn_def[i]); end if;
  end loop;
  select string_agg(t.tgrelid::regclass::text || '.' || t.tgname, ', ' order by 1) into d
    from pg_trigger t where t.tgname in (c_trg_name, 'payment_method_wallet_locked') and not t.tgisinternal;
  if d is not null then
    raise exception '532: a trigger of 532''s name is already there (%). Re-read it before applying.', d; end if;
  -- Relied on.
  for i in 1 .. cardinality(c_relied) loop
    if to_regprocedure('public.' || c_relied[i]) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i]))) <> c_relied_md5[i] then
      raise exception '532: public.% is missing or not the version this was tested against. Re-read it and re-test before applying.', c_relied[i];
    end if;
  end loop;
  select pg_get_triggerdef(t.oid) into d from pg_trigger t
   where t.tgrelid = 'public.profiles'::regclass and t.tgname = 'staff_login_follows_profile';
  if d is distinct from c_412_trg or not (c_trg_name < 'staff_login_follows_profile') then
    raise exception '532: 412''s trigger on public.profiles is not the tested one (%)', coalesce(d, 'missing'); end if;
  for i in 1 .. cardinality(c_route) loop
    if not exists (select 1 from pg_proc p
                    where p.oid = to_regprocedure('public.' || c_route[i]) and p.prosecdef
                      and has_function_privilege('authenticated', p.oid, 'execute')) then
      raise exception '532: public.% is missing, not SECURITY DEFINER, or not open to signed-in logins: a page saves through it once the table''s write rules are gone. Re-read it before applying.', c_route[i];
    end if;
  end loop;
  -- The columns read, and the wallet settings' defaults.
  for i in 1 .. cardinality(c_cols) loop
    v_tab := split_part(c_cols[i], ':', 1);
    v_want := split_part(c_cols[i], ':', 2);
    select string_agg(a.attname || ' ' || format_type(a.atttypid, a.atttypmod), '|' order by a.attname) into v_have
      from pg_attribute a
     where a.attrelid = to_regclass('public.' || v_tab) and a.attnum > 0 and not a.attisdropped
       and a.attname = any (string_to_array(regexp_replace(v_want, ' [^|]+', '', 'g'), '|'));
    if v_have is distinct from v_want then
      raise exception '532: the columns of public.% are not the tested ones (% instead of %)', v_tab, coalesce(v_have, 'none'), v_want; end if;
  end loop;
  select string_agg(c.column_name || '=' || coalesce(c.column_default, ''), '|' order by c.column_name) into v_have
    from information_schema.columns c
   where c.table_schema = 'public' and c.table_name = 'payment_methods'
     and c.column_name in ('is_wallet_credit', 'wallet_category', 'wallet_source', 'is_system');
  if v_have is distinct from c_pm_defaults then
    raise exception '532: the defaults of a payment method''s wallet settings are not the tested ones (%)', v_have; end if;
  -- The thirteen tables are there, as tables with row level security.
  for i in 1 .. cardinality(c_trg_table) loop
    if not exists (select 1 from pg_class c where c.oid = to_regclass('public.' || c_trg_table[i])
                    and c.relkind = 'r' and c.relrowsecurity) then
      raise exception '532: public.% is missing or has no row level security', c_trg_table[i]; end if;
  end loop;
  -- The store rules: as tested.
  if not exists (select 1 from pg_policy p where p.polrelid = 'public.stores'::regclass and p.polname = 'update stores'
                  and p.polcmd = 'w' and p.polpermissive and p.polroles = array['authenticated'::regrole::oid]
                  and pg_get_expr(p.polqual, p.polrelid) = c_st_om and pg_get_expr(p.polwithcheck, p.polrelid) = c_st_om)
     or not exists (select 1 from pg_policy p where p.polrelid = 'public.stores'::regclass and p.polname = 'insert stores'
                  and p.polcmd = 'a' and p.polpermissive and p.polroles = array['authenticated'::regrole::oid]
                  and p.polqual is null and pg_get_expr(p.polwithcheck, p.polrelid) = c_st_om)
     or (select count(*) from pg_policy p where p.polrelid = 'public.stores'::regclass and p.polcmd <> 'r') <> 2 then
    raise exception '532: the write rules of public.stores are not the ones this was tested against. Re-read them before applying.'; end if;
  -- The store functions: BEFORE, with their grants, and their patch found once.
  for i in 1 .. cardinality(c_sig) loop
    if to_regprocedure('public.' || c_sig[i]) is null then raise exception '532: public.% is missing', c_sig[i]; end if;
    d := pg_get_functiondef(to_regprocedure('public.' || c_sig[i]));
    if md5(d) <> c_before[i] then
      raise exception '532: public.% is not the version this was tested against (md5 %). Re-read it and re-test before applying.', c_sig[i], md5(d); end if;
    if (select coalesce(string_agg(x::text, ',' order by x::text), '')
          from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig[i])) is distinct from c_acl[i] then
      raise exception '532: the grants of public.% are not the tested ones', c_sig[i]; end if;
    if (length(d) - length(replace(d, c_anchor[i], ''))) / length(c_anchor[i]) <> 1 then
      raise exception '532: the patch of public.% does not find its text exactly once', c_sig[i]; end if;
    v_def[i] := replace(d, c_anchor[i], c_new[i]);
    if md5(v_def[i]) <> c_after[i] then
      raise exception '532: the patched text of public.% is not the tested one (md5 %)', c_sig[i], md5(v_def[i]); end if;
  end loop;
  -- The store images' rules on storage.objects: each as tested, and no other rule for the bucket.
  for i in 1 .. cardinality(c_sa_pol) loop
    if not exists (select 1 from pg_policy p
                    where p.polrelid = 'storage.objects'::regclass and p.polname = c_sa_pol[i]
                      and p.polcmd = c_sa_cmd[i]::"char" and p.polpermissive and p.polroles::regrole[]::text = c_sa_roles[i]
                      and pg_get_expr(p.polqual, p.polrelid) is not distinct from c_sa_qual[i]
                      and pg_get_expr(p.polwithcheck, p.polrelid) is not distinct from c_sa_check[i]) then
      raise exception '532: the rule "%" on storage.objects is not the one this was tested against. Re-read it before applying.', c_sa_pol[i]; end if;
  end loop;
  if exists (select 1 from pg_policy p where p.polrelid = 'storage.objects'::regclass and p.polname <> all (c_sa_pol)
              and coalesce(pg_get_expr(p.polqual, p.polrelid), '') || coalesce(pg_get_expr(p.polwithcheck, p.polrelid), '') like '%store-assets%') then
    raise exception '532: another rule on storage.objects names the store-assets bucket. Re-read it before applying.'; end if;
  -- The helpers the new rules call run as the signed-in login.
  for i in 1 .. cardinality(c_rule_helpers) loop
    if not has_function_privilege('authenticated', to_regprocedure('public.' || c_rule_helpers[i]), 'execute') then
      raise exception '532: public.% is not open to signed-in logins, so a rule calling it would refuse everyone', c_rule_helpers[i]; end if;
  end loop;
  -- The rules dropped: each as tested.
  for i in 1 .. cardinality(c_pol_table) loop
    select count(*) into n
      from pg_policy p
     where p.polrelid = to_regclass('public.' || c_pol_table[i]) and p.polname = c_pol_name[i]
       and p.polcmd = c_pol_cmd[i]::"char" and p.polpermissive
       and p.polroles = array['authenticated'::regrole::oid]
       and pg_get_expr(p.polqual, p.polrelid) is not distinct from c_pol_qual[i]
       and pg_get_expr(p.polwithcheck, p.polrelid) is not distinct from c_pol_check[i];
    if n <> 1 then
      v_bad := v_bad || format(E'\n  %s "%s": %s', c_pol_table[i], c_pol_name[i],
        coalesce((select format('cmd %s, roles %s, permissive %s, using %s, with check %s', p.polcmd, p.polroles::regrole[],
                                p.polpermissive, pg_get_expr(p.polqual, p.polrelid), pg_get_expr(p.polwithcheck, p.polrelid))
                    from pg_policy p where p.polrelid = to_regclass('public.' || c_pol_table[i]) and p.polname = c_pol_name[i]),
                 'missing'));
    end if;
  end loop;
  if v_bad <> '' then
    raise exception '532: these rules are not the ones this was tested against. Re-read them before applying:%', v_bad; end if;
  for i in 1 .. cardinality(c_keep_table) loop
    if not exists (select 1 from pg_policy p where p.polrelid = to_regclass('public.' || c_keep_table[i])
                    and p.polname = c_keep_name[i] and p.polcmd = c_keep_cmd[i]::"char") then
      raise exception '532: the rule "%" on public.%, which a page still uses, is missing', c_keep_name[i], c_keep_table[i]; end if;
  end loop;

  -- 2. Install
  for i in 1 .. cardinality(c_fn_sig) loop
    execute c_fn_def[i];
    execute format('revoke all on function public.%s from public, anon, authenticated, service_role', c_fn_sig[i]);
    execute format('grant execute on function public.%s to service_role', c_fn_sig[i]);
  end loop;
  for i in 1 .. cardinality(c_trg_table) loop
    execute format('create trigger %I after %s on public.%I for each row '
                   'when (current_user in (''anon'', ''authenticated'', ''service_role'')) '
                   'execute function public.trg_audit_direct_change()', c_trg_name, lower(c_trg_ops[i]), c_trg_table[i]);
  end loop;
  execute 'create trigger payment_method_wallet_locked before insert or update on public.payment_methods for each row '
          'when (current_user in (''anon'', ''authenticated'', ''service_role'')) '
          'execute function public.trg_payment_method_wallet_locked()';
  execute format('alter policy %I on public.stores using (%s) with check (%s)', 'update stores', c_st_upd_src, c_st_upd_src);
  execute format('alter policy %I on public.stores with check (%s)', 'insert stores', c_st_ins_src);
  execute format('alter policy %I on storage.objects with check (%s)', 'store-assets write', c_sa_write_src);
  execute 'drop policy "store-assets update" on storage.objects';
  execute 'drop policy "store-assets delete" on storage.objects';
  for i in 1 .. cardinality(c_sig) loop
    execute v_def[i];
  end loop;
  for i in 1 .. cardinality(c_pol_table) loop
    execute format('drop policy %I on public.%I', c_pol_name[i], c_pol_table[i]);
  end loop;

  -- 3. Checks after installing
  for i in 1 .. cardinality(c_fn_sig) loop
    if md5(pg_get_functiondef(to_regprocedure('public.' || c_fn_sig[i]))) <> c_fn_md5[i] then
      raise exception '532: public.% was installed with an md5 other than the tested one (md5 %)', c_fn_sig[i],
        md5(pg_get_functiondef(to_regprocedure('public.' || c_fn_sig[i]))); end if;
    if (select coalesce(string_agg(x::text, ',' order by x::text), '')
          from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_fn_sig[i])) is distinct from c_fn_acl then
      raise exception '532: the rights on public.% are not the tested ones', c_fn_sig[i]; end if;
  end loop;
  for i in 1 .. cardinality(c_trg_table) loop
    select pg_get_triggerdef(t.oid) into d from pg_trigger t
     where t.tgrelid = to_regclass('public.' || c_trg_table[i]) and t.tgname = c_trg_name;
    if d is distinct from format(c_trg_def, c_trg_ops[i], c_trg_table[i]) then
      raise exception '532: the trigger on public.% is not the tested one (%)', c_trg_table[i], coalesce(d, 'missing'); end if;
  end loop;
  if (select count(*) from pg_trigger t where t.tgfoid = to_regprocedure('public.' || c_fn_sig[1])) <> cardinality(c_trg_table) then
    raise exception '532: public.% is not used by exactly the % triggers', c_fn_sig[1], cardinality(c_trg_table); end if;
  if (select string_agg(pg_get_triggerdef(t.oid), ';') from pg_trigger t where t.tgfoid = to_regprocedure('public.' || c_fn_sig[2]))
     is distinct from c_pm_trg_def then
    raise exception '532: the trigger of public.% is not the tested one', c_fn_sig[2]; end if;
  if (select pg_get_expr(p.polqual, p.polrelid) || ' / ' || pg_get_expr(p.polwithcheck, p.polrelid) from pg_policy p
       where p.polrelid = 'public.stores'::regclass and p.polname = 'update stores') is distinct from c_st_upd_after || ' / ' || c_st_upd_after
     or (select pg_get_expr(p.polwithcheck, p.polrelid) from pg_policy p
          where p.polrelid = 'public.stores'::regclass and p.polname = 'insert stores') is distinct from c_st_ins_after then
    raise exception '532: the store rules are not as tested: %', (select string_agg(p.polname || ': ' || coalesce(pg_get_expr(p.polqual, p.polrelid), '-')
      || ' / ' || coalesce(pg_get_expr(p.polwithcheck, p.polrelid), '-'), '; ') from pg_policy p where p.polrelid = 'public.stores'::regclass and p.polcmd <> 'r'); end if;
  for i in 1 .. cardinality(c_sig) loop
    if md5(pg_get_functiondef(to_regprocedure('public.' || c_sig[i]))) <> c_after[i] then
      raise exception '532: public.% was installed with an md5 other than the tested one', c_sig[i]; end if;
    if (select coalesce(string_agg(x::text, ',' order by x::text), '')
          from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig[i])) is distinct from c_acl[i] then
      raise exception '532: the grants of public.% changed', c_sig[i]; end if;
  end loop;
  for i in 1 .. cardinality(c_pol_table) loop
    if exists (select 1 from pg_policy p where p.polrelid = to_regclass('public.' || c_pol_table[i]) and p.polname = c_pol_name[i]) then
      raise exception '532: the rule "%" on public.% is still there', c_pol_name[i], c_pol_table[i]; end if;
  end loop;
  if (select string_agg(p.polname || ' ' || p.polcmd::text || ' ' || coalesce(pg_get_expr(p.polqual, p.polrelid), '-') || ' / '
                        || coalesce(pg_get_expr(p.polwithcheck, p.polrelid), '-'), '; ' order by p.polname)
        from pg_policy p where p.polrelid = 'storage.objects'::regclass and p.polname = any (c_sa_pol))
     is distinct from c_sa_pol[1] || ' r ' || c_sa_qual[1] || ' / -; ' || c_sa_pol[2] || ' a - / ' || c_sa_write_after then
    raise exception '532: the store-assets rules are not as tested'; end if;
  for i in 1 .. cardinality(c_keep_table) loop
    if not exists (select 1 from pg_policy p where p.polrelid = to_regclass('public.' || c_keep_table[i])
                    and p.polname = c_keep_name[i] and p.polcmd = c_keep_cmd[i]::"char") then
      raise exception '532: the rule "%" on public.% went', c_keep_name[i], c_keep_table[i]; end if;
  end loop;
  for i in 1 .. cardinality(c_relied) loop
    if md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i]))) <> c_relied_md5[i] then
      raise exception '532: public.% changed', c_relied[i]; end if;
  end loop;

  perform set_config('lock_timeout', v_lock, true);
  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $mig$;
