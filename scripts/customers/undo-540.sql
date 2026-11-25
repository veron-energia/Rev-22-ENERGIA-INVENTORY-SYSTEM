-- UNDO of 540 (with the user's go-ahead). It takes 540's text out of the 68 functions it changed
-- (the guard line inventory_manager_guard(...) first in 66, and the patches in stock_loan_json,
-- report_foc_lines, lend_stock and return_stock_loan), putting each back exactly
-- as before 540 (md5s below); puts the 24 read rules (invoices, invoice_handovers,
-- invoice_voucher_movements, product_exchanges, therapy_entitlement_invoices, document_sends,
-- stock_loans, the 15 tables of customer benefits, rentals and special_sales) back as they were; drops the three no_invoicing_for_inventory_managers triggers and
-- the two functions 540 made (inventory_manager_guard, no_invoicing_for_inventory_managers).
-- Afterwards an Inventory Manager of a store makes, reads and changes its invoices again, lends
-- and takes back stock, and reads customers' names in the invoice, exchange and therapy functions
-- (539 still closes the customer list): the M13 "Stock only" rule open again. Stock movement notes
-- written since 540 keep the loan number only. Run it BEFORE scripts/customers/undo-539.sql.
--
-- It refuses, with nothing changed, unless every function, rule and trigger 540 made or changed is
-- exactly 540's and no other function calls the new ones. One transaction, all or nothing; it waits
-- at most 5 seconds for a lock. The 540 row in supabase_migrations.schema_migrations stays; with the
-- user's OK, remove that one row or record this UNDO beside it.
do $undo$
declare
  c_sig constant text[] := array[
    'affiliate_staff_directory(text,integer,integer)',
    'customer_match_candidates(text,text)',
    'customer_overview(uuid)',
    'exchange_bundle_preview(uuid,uuid,uuid,uuid)',
    'exchange_credit_preview(uuid,uuid)',
    'exchange_ineligibility_reason(uuid)',
    'exchange_invoice_details(uuid)',
    'invoice_bill_to_source(uuid)',
    'invoice_credit_receivers(uuid)',
    'invoice_credit_reward_entitlements(uuid,uuid)',
    'invoice_event_guests(uuid)',
    'invoice_events(uuid[])',
    'invoice_financial_position(uuid)',
    'invoice_goods_status(uuid)',
    'invoice_list_goods_out(uuid[])',
    'invoice_payment_credit_sources(uuid)',
    'invoice_rentals_awaiting_return(uuid)',
    'invoice_request_status(uuid)',
    'invoice_revision_history(uuid)',
    'invoice_stock_component_evidence(uuid)',
    'invoice_transferable_benefits(uuid)',
    'purchased_therapy_units(uuid,uuid,boolean)',
    'record_document_printed(text,uuid)',
    'report_discounts()',
    'report_exchange_invoices(uuid,date,date)',
    'set_invoice_instalment_label(uuid,uuid,integer)',
    'therapy_closure_impact(date,text,text)',
    'therapy_recalculation_preview(text,uuid)',
    'customer_stock_loans(uuid)',
    'exchange_original_context(uuid)',
    'invoice_action_plan(uuid,text,jsonb)',
    'invoice_display_names(uuid)',
    'invoice_effective_affiliate(uuid)',
    'invoice_list_page(text,text,text,date,date,uuid,text,text,integer,integer)',
    'invoice_refund_options(uuid)',
    'preview_invoice_correction(uuid,jsonb)',
    'report_pricing()',
    'therapy_customer_detail(uuid)',
    'activate_purchased_therapy(uuid,date,text,text,text,boolean)',
    'choose_therapy_benefit(uuid,text,uuid,text)',
    'reschedule_purchased_therapy(uuid,date,text)',
    'claim_entitlement_vouchers(uuid,jsonb,text,uuid)',
    'claim_purchased_therapy(uuid,text,date,text,text,boolean,jsonb,uuid,text)',
    'create_exchange_with_details(text,jsonb)',
    'create_invoice_with_details(uuid,uuid,jsonb,jsonb)',
    'create_split_credit_package_invoices(uuid,uuid,jsonb,uuid[],uuid,text,uuid)',
    'create_split_premium_bundle_invoices(uuid,uuid,jsonb,uuid[],uuid,text,uuid)',
    'correct_invoice(uuid,jsonb,jsonb,text,uuid)',
    'delete_invoice(uuid,text)',
    'event_guest_list(uuid)',
    'event_invoices(uuid)',
    'event_planning_summary(uuid)',
    'event_save_guest(jsonb)',
    'exchange_payment_position(uuid)',
    'invoice_action_request_detail(uuid)',
    'record_document_send(text,text,text,uuid,uuid,text,text,text,text)',
    'record_invoice_handover(uuid,jsonb,uuid)',
    'record_invoice_settlement(uuid,jsonb,uuid)',
    'request_invoice_action_v2(uuid,text,jsonb,text,text,uuid)',
    'therapy_list_page(text,text,text,integer,integer)',
    'lend_stock(text,uuid,jsonb,date,uuid,text,text,uuid)',
    'return_stock_loan(uuid,jsonb,text,uuid)',
    'customer_therapy_session_balance(uuid)',
    'customer_therapy_voucher_rights(uuid,date)',
    'therapy_customer_entitlements(uuid,date)',
    'therapy_customer_service_summary(uuid,date)',
    'stock_loan_json(uuid)',
    'report_foc_lines(date,date,uuid)'];
  c_kind constant text[] := array[
    'stock',
    'stock',
    'stock',
    'stock',
    'stock',
    'stock',
    'stock',
    'stock',
    'stock',
    'stock',
    'stock',
    'stock',
    'stock',
    'stock',
    'stock',
    'stock',
    'stock',
    'stock',
    'stock',
    'stock',
    'stock',
    'stock',
    'stock',
    'stock',
    'stock',
    'invoice',
    'stock',
    'stock',
    'stock',
    'stock',
    'stock',
    'stock',
    'stock',
    'stock',
    'stock',
    'invoice',
    'stock',
    'stock',
    'stock',
    'stock',
    'stock',
    'invoice',
    'invoice',
    'invoice',
    'invoice',
    'invoice',
    'invoice',
    'invoice',
    'invoice',
    'stock',
    'stock',
    'stock',
    'stock',
    'stock',
    'stock',
    'stock',
    'invoice',
    'invoice',
    'invoice',
    'stock',
    'loan',
    'loan',
    'stock',
    'stock',
    'stock',
    'stock',
    null,
    null];
  c_before constant text[] := array[
    '1db82f16aa93d1e2f967be0be3be62db',
    'acb7756d5d08b2b316cadee6ab1adba0',
    '91912a72aab437420f16cd7fe3b67da2',
    'c09fce506c8b92c321e8cf0f589691ff',
    '263bb91b1ed38c6b53767c4d0182595c',
    '869985df7601d401df40f44c40dd2d6e',
    '45791e627e1616ab7edad181139a2d83',
    'f46d331ce5410681dfcb73ace9600ca3',
    'ecdd2c5a5051cca33a9cedd0a5c07666',
    '58af19ba437802ecdfc1d559091e8e5d',
    '64a1a3ca025595126cd88db6034f9736',
    '10a4aae88e1c094618e108df88e9ad5a',
    'ba7eccbfeff217c8b1969b0e55a010ca',
    'ca966a2c6a1949afc98503862263b58d',
    '6c9da48db53c8febe2cb7a7188740398',
    'bf9f73f9363614794da78d24cd118dcc',
    '07621bd5ba0b8be5cf69460ac4212017',
    '3930f9e6de6a53de9bb78302e7fc37e2',
    '4b5143e1d62e17ae83c1cd7ff507aecf',
    '5b3acdd32112bfa4ab578fcdc728614c',
    '1546de1f83d970424d26e65941f4dcb8',
    '9da46e18c367c76b5c3c2c2fe32a332d',
    'b67386018227a05327874c57e2acb9d2',
    '8851419fba9504cdf8093792e60ae2b3',
    '298d3f07deab82be159e64855c03ada4',
    '8ff9ae95f434a0123d130b46527207ef',
    'bb10dcaf76d34eb9045834630269a7de',
    'a8b19d4965bc2e153cff00159234d3c0',
    '72ea1935e18db21c6ee75d09568d9ecf',
    '45cfb42ee4c91a983e3cc546f4a655b3',
    'd8bf5ea6c92c49be3b53547e6f407278',
    'a182dcf899c3490a8a5f448611877aa5',
    'ca12ec55c032fd6475c2d7eb5832dce7',
    '2c0017c93df1d7eb10f6eb44f63fb7b7',
    '0a9276f8b967b24a040e486287182072',
    '23c180873b6545bd83fb20d21708aa9e',
    '957d112c55edb92fcf9d22c4faa2253d',
    '8c9143f82bfda412f26e743dbad47181',
    '1047cc5c2ed136ae4fd22d0b471c4199',
    'bf419bd6487f392a6ab2b5b302cf48f5',
    '52b37e85c1677199a2335b31f24ac4a3',
    'ceccabc80c3015aec2172de0f6cbde65',
    'c833e4cbfd01b3de4d825b5f6080e73e',
    '82cdd84bf325a4ea5a49ea665f2d3404',
    '0d60261bf337a1716dab9307b2f52fea',
    'd9219dc95c3f5f598085161d31744d16',
    'dfef28574f9c5b827d1093df1b5fc9b3',
    'aaf592490eb5d13ca2ccb0544f48f647',
    '530b8217e94c9bbb0765c47da2d8d40e',
    'cbe2f3ef06fe97e59fc2e3b19fd35cac',
    'f2c7aa8295b94c2018e5284d39a801fd',
    'dcdbde542fc6dd791ce9c01eb1f7096c',
    'f828b8558735696b392ae0f2e6c64a24',
    '72f67782f592fcac1254d7eb1961e37a',
    'df67842de673e4ec37890c027c52e0d9',
    'b602db515c9a685bf6fe642eb312b4ab',
    '1132398e57a234deb60c972fc89a8ffa',
    '8c8778af82899c6aaada62371d13802f',
    '4360d74462ed1fc950b6bd8b5157b3ae',
    '729ae2d27eadbf2a996dac13d608629c',
    'fcea544234f910ccecad12f185bdf753',
    'c79caeb845c31b3032f90df3d0e01778',
    '1be9708e3d42a822c6f2dae7f702ac80',
    '47ff93e41039dad975b27851b1b2ae0d',
    '4c5813043c83d3849d4b8cd300bd8a8f',
    '5fbe8464b8cc0ac3fa72ee5d63b9b09e',
    'd9726b2be1578afc7915fe6995db5206',
    '043595acb106e493eda8cee8dada9612'];
  c_540 constant text[] := array[
    '61595fb38791f91eecdeb0d51763fce3',
    'f38e1bc8b137d362da3830230442f46a',
    'f45ba15f1f08ea8e3f349ed9bd8e4389',
    'ef186f36a441000c0788a368fa545489',
    'e61c362d0a4651d00e67ebc4aa58bf3a',
    '5266700b328bcd0c59b3390b87dc172c',
    '71fb83853e9edc938dc68eb43331b679',
    '07769b23a749e7b29963ad1acfe4e2c5',
    'f32bd80b674a005f831a7abc8b88b6c8',
    'adb226dd8cac21d5a590f61f55111e61',
    '2be5743f29f8a5b4cc8e5d16c804655b',
    'b0e945789ade7c7667cb032739550120',
    'f43495aca62114837339315d9e2170a1',
    '7b6a7ef94e17eb6b8cab0581f15e7851',
    '353784e17a87c62f4c7daaaad21f4578',
    '31ef394f5dbfce456482d13b27049047',
    '1d856d15a3e4d65bdd8ccddb4c387b3d',
    '482b1056596386ba8b1e717686b55562',
    'c189645d076684086a9bac0b3bdb8b24',
    'a48b1a0fc4428319abf977db7245f056',
    'b7ea433dac312f07ee3d75d0da569e93',
    'ee90cf067b5f11e14871329eef44500b',
    'de4ca18ab28c006396a2f58005eac876',
    '9834f6df05bb1bf7175360e8c6435839',
    'ecd874a1f31a70226a8329511282fde6',
    '810c8b81c3f2d86f9962e3322ba1dd6a',
    '0c670bf9e32898251cb4efd2b0041560',
    'a2f763c220414809986677bffe41749e',
    '9e91aed33b5fae9ed71c18294a00c849',
    '63780a5138efe44ad901ad1a96b1c7b4',
    '7454af269896b1587e0ed711f7ad37eb',
    'c39dbd6e1a9ef048a67cacc4236ad41d',
    '9ca28abe5b9b5d0d5e656e3a6efb83fe',
    '10cffaedb46fa7c8c82cf545a6d0a3b1',
    'c4459735f72b2c974d04a943f59df668',
    'eda7b1aa557d8b1dea5a5d7701cea750',
    '79dceaadf78b04f086390111314a6e26',
    '98d64c43418f7e30ccc77b2487cdf744',
    '818926f15f570aa479e7661546ab77ea',
    'd6dbc0122e54eed35044f0831a975179',
    '09511a55622f562bea29a6f378d37029',
    'ce43e887b87051e4148eed61945eb51b',
    '89af49522a7523afe7f17ca2d6b0ced7',
    '65aceebfba200138e5e2d654b44253bb',
    '2b94f8365bb1e16d59aaaf175453788b',
    '56d508be01e66054d6590b68af0aa9c9',
    '28aede2f9ad40bcc9f7e279df86f97bc',
    'dce00002cbcc4ae290ff23e2273f5e4c',
    'adb06df0438934f4944a966044f864e5',
    '000cdefee03a5fd7ec88f37d5c794788',
    '082408df7e433997b645bd1ebb4e8692',
    '03a324c4415ba5ff4838e28d79897452',
    '896ea632b9cc5b1dd3b470a66ae57249',
    'a4b047c06d94187fdf92f71bf32cf73a',
    'c91613824dc7894cc3fc933898f5678c',
    '320bcaf73c2dca235f8a4c186f255e20',
    'a21a19711bdc521c09c8b5c967c6d77b',
    '74b29c82e1717695dacbf3768f34c588',
    '44e4e334c3b7440399427762c87d0e54',
    '345a81f32ffd089a16594a3d22aa7e7a',
    'b4bec98e231490a9e9f6cb833496981e',
    '4a3346c3e7cebee4e9a9054d587dacb2',
    '26dd8a168db60b8360c56e315c2b7351',
    '192667dbe30dda92cee2d766129a9f02',
    'edf6e6912d24016497953069d9d6a463',
    'e04d53ddff60b3078b605f1b2bac7ce1',
    'bbb26cf84086e5dede1ca2890ace819d',
    '36230b6d31ca05eb4528618f618b69af'];
  c_acl constant text[] := array[
    'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres',
    'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres',
    'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres',
    'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres',
    'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres',
    'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres',
    'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres',
    'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres',
    'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres',
    'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres',
    'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres',
    'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres',
    'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres',
    'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres',
    'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres',
    'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres',
    'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres',
    'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres',
    'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres',
    'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres',
    'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres',
    'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres',
    'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres',
    'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres',
    'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres',
    'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres',
    'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres',
    'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres',
    'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres',
    'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres',
    'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres',
    'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres',
    'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres',
    'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres',
    'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres',
    'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres',
    'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres',
    'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres',
    'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres',
    'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres',
    'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres',
    'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres',
    'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres',
    'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres',
    'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres',
    'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres',
    'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres',
    'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres',
    'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres',
    'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres',
    'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres',
    'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres',
    'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres',
    'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres',
    'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres',
    'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres',
    'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres',
    'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres',
    'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres',
    'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres',
    'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres',
    'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres',
    'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres',
    'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres',
    'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres',
    'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres',
    'postgres=X/postgres,service_role=X/postgres',
    'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres'];
  c_fn constant int[] := array[67, 68, 61, 62];
  c_anchor constant text[] := array[
$a$               where e.loan_id = l.id))
    from public.stock_loans l$a$,
$a$  select i.id, i.invoice_no, i.status, i.store_id,
         c.full_name,$a$,
$a$      v_loan.loan_no || ' — lent to ' || v_borrower || coalesce(' (' || v_purpose || ')', '')$a$,
$a$        l.loan_no || ' — returned by ' || v_borrower$a$];
  c_new constant text[] := array[
$n$               where e.loan_id = l.id))
         -- 540 (security audit of 17 Nov 2026, M13; the user, 25 Nov 2026: "Stock only"): no
         -- borrower's name or phone for an Inventory Manager.
         - case when public.current_user_role() = 'inventory_manager' then array['borrower', 'borrower_phone'] else '{}'::text[] end
    from public.stock_loans l$n$,
$n$  select i.id, i.invoice_no, i.status, i.store_id,
         -- 540 (security audit of 17 Nov 2026, M13; the user, 25 Nov 2026: "Stock only"): the
         -- Dashboard's FOC totals stay an Inventory Manager's; the customer's name does not.
         case when public.current_user_role() is distinct from 'inventory_manager' then c.full_name end,$n$,
$n$      -- 540 (the user, 25 Nov 2026): the loan number, not the borrower (who stays on the loan).
      v_loan.loan_no || ' lent' || coalesce(' (' || v_purpose || ')', '')$n$,
$n$        -- 540 (the user, 25 Nov 2026): the loan number, not the borrower (who stays on the loan).
        l.loan_no || ' returned'$n$];
  c_guard_pl constant text := '  perform public.inventory_manager_guard(%L);  -- 540 (security audit of 17 Nov 2026, M13; the user, 25 Nov 2026: "Stock only")' || E'\n';
  c_guard_sql constant text := '  select public.inventory_manager_guard(%L);  -- 540 (security audit of 17 Nov 2026, M13; the user, 25 Nov 2026: "Stock only")' || E'\n';
  c_pol_table constant text[] := array[
    'credit_package_sales',
    'credit_package_split_allocations',
    'customer_affiliates',
    'customer_reward_vouchers',
    'customer_therapy_sessions',
    'document_sends',
    'invoice_handovers',
    'invoice_voucher_movements',
    'invoices',
    'premium_bundle_sales',
    'premium_bundle_split_allocations',
    'product_exchanges',
    'purchased_therapy_entitlements',
    'rentals',
    'special_credit_allocations',
    'special_sales',
    'stock_loans',
    'therapy_entitlement_invoices',
    'therapy_entitlements',
    'therapy_expiry_adjustments',
    'therapy_qualification_topups',
    'therapy_voucher_issues',
    'voucher_claims',
    'voucher_redemptions'];
  c_pol_name constant text[] := array[
    'read package sales',
    'read split allocations',
    'read affiliates',
    'read reward vouchers',
    'read therapy sessions',
    'read document sends',
    'invoice_handovers_read',
    'invoice_voucher_movements_read',
    'read invoices',
    'read premium bundles',
    'read bundle split allocations',
    'read exchanges',
    'read pte',
    'read rentals',
    'read special credit allocations',
    'read special sales',
    'read stock loans',
    'read ent invoices',
    'read entitlements',
    'read_adjustments',
    'read qual topups',
    'read voucher issues',
    'read voucher claims',
    'read voucher redemptions'];
  c_pol_before constant text[] := array[
    '(( SELECT current_user_role() AS current_user_role) IS NOT NULL)',
    '(( SELECT current_user_role() AS current_user_role) IS NOT NULL)',
    '(( SELECT current_user_role() AS current_user_role) IS NOT NULL)',
    '(( SELECT current_user_role() AS current_user_role) IS NOT NULL)',
    '(( SELECT current_user_role() AS current_user_role) IS NOT NULL)',
    '(( SELECT current_user_role() AS current_user_role) IS NOT NULL)',
    '(( SELECT is_owner_or_admin() AS is_owner_or_admin) OR (store_id = ANY (( SELECT current_user_store_ids() AS current_user_store_ids)::uuid[])))',
    '(( SELECT is_owner_or_admin() AS is_owner_or_admin) OR (store_id = ANY (( SELECT current_user_store_ids() AS current_user_store_ids)::uuid[])))',
    '(( SELECT is_owner_or_admin() AS is_owner_or_admin) OR (store_id = ANY (( SELECT current_user_store_ids() AS current_user_store_ids)::uuid[])))',
    '(( SELECT current_user_role() AS current_user_role) IS NOT NULL)',
    '(( SELECT current_user_role() AS current_user_role) IS NOT NULL)',
    '(( SELECT is_manager_or_above() AS is_manager_or_above) OR (( SELECT is_owner_or_admin() AS is_owner_or_admin) OR (processing_store_id = ANY (( SELECT current_user_store_ids() AS current_user_store_ids)::uuid[]))))',
    '((current_user_role() IS NOT NULL) AND user_has_store_access(store_id))',
    '(( SELECT is_manager_or_above() AS is_manager_or_above) OR (store_id = ANY (( SELECT current_user_store_ids() AS current_user_store_ids)::uuid[])) OR (source_store_id = ANY (( SELECT current_user_store_ids() AS current_user_store_ids)::uuid[])))',
    '(( SELECT current_user_role() AS current_user_role) IS NOT NULL)',
    '(( SELECT is_manager_or_above() AS is_manager_or_above) OR (store_id = ANY (( SELECT current_user_store_ids() AS current_user_store_ids)::uuid[])) OR (source_store_id = ANY (( SELECT current_user_store_ids() AS current_user_store_ids)::uuid[])))',
    '(( SELECT is_manager_or_above() AS is_manager_or_above) OR ((store_id IS NOT NULL) AND (( SELECT is_owner_or_admin() AS is_owner_or_admin) OR (store_id = ANY (( SELECT current_user_store_ids() AS current_user_store_ids)::uuid[])))) OR ((warehouse_id IS NOT NULL) AND ( SELECT can_manage_warehouse_stock() AS can_manage_warehouse_stock)))',
    '(( SELECT current_user_role() AS current_user_role) IS NOT NULL)',
    '(( SELECT is_manager_or_above() AS is_manager_or_above) OR (( SELECT is_owner_or_admin() AS is_owner_or_admin) OR (store_id = ANY (( SELECT current_user_store_ids() AS current_user_store_ids)::uuid[]))))',
    '(( SELECT current_user_role() AS current_user_role) IS NOT NULL)',
    '(( SELECT current_user_role() AS current_user_role) IS NOT NULL)',
    '(( SELECT current_user_role() AS current_user_role) IS NOT NULL)',
    '(( SELECT is_owner_or_admin() AS is_owner_or_admin) OR (store_id = ANY (( SELECT current_user_store_ids() AS current_user_store_ids)::uuid[])))',
    '(( SELECT current_user_role() AS current_user_role) IS NOT NULL)'];
  c_pol_540 constant text[] := array[
    '((( SELECT current_user_role() AS current_user_role) IS DISTINCT FROM ''inventory_manager''::user_role) AND (( SELECT current_user_role() AS current_user_role) IS NOT NULL))',
    '((( SELECT current_user_role() AS current_user_role) IS DISTINCT FROM ''inventory_manager''::user_role) AND (( SELECT current_user_role() AS current_user_role) IS NOT NULL))',
    '((( SELECT current_user_role() AS current_user_role) IS DISTINCT FROM ''inventory_manager''::user_role) AND (( SELECT current_user_role() AS current_user_role) IS NOT NULL))',
    '((( SELECT current_user_role() AS current_user_role) IS DISTINCT FROM ''inventory_manager''::user_role) AND (( SELECT current_user_role() AS current_user_role) IS NOT NULL))',
    '((( SELECT current_user_role() AS current_user_role) IS DISTINCT FROM ''inventory_manager''::user_role) AND (( SELECT current_user_role() AS current_user_role) IS NOT NULL))',
    '((( SELECT current_user_role() AS current_user_role) IS DISTINCT FROM ''inventory_manager''::user_role) AND (( SELECT current_user_role() AS current_user_role) IS NOT NULL))',
    '((( SELECT current_user_role() AS current_user_role) IS DISTINCT FROM ''inventory_manager''::user_role) AND (( SELECT is_owner_or_admin() AS is_owner_or_admin) OR (store_id = ANY (( SELECT current_user_store_ids() AS current_user_store_ids)::uuid[]))))',
    '((( SELECT current_user_role() AS current_user_role) IS DISTINCT FROM ''inventory_manager''::user_role) AND (( SELECT is_owner_or_admin() AS is_owner_or_admin) OR (store_id = ANY (( SELECT current_user_store_ids() AS current_user_store_ids)::uuid[]))))',
    '((( SELECT current_user_role() AS current_user_role) IS DISTINCT FROM ''inventory_manager''::user_role) AND (( SELECT is_owner_or_admin() AS is_owner_or_admin) OR (store_id = ANY (( SELECT current_user_store_ids() AS current_user_store_ids)::uuid[]))))',
    '((( SELECT current_user_role() AS current_user_role) IS DISTINCT FROM ''inventory_manager''::user_role) AND (( SELECT current_user_role() AS current_user_role) IS NOT NULL))',
    '((( SELECT current_user_role() AS current_user_role) IS DISTINCT FROM ''inventory_manager''::user_role) AND (( SELECT current_user_role() AS current_user_role) IS NOT NULL))',
    '((( SELECT current_user_role() AS current_user_role) IS DISTINCT FROM ''inventory_manager''::user_role) AND (( SELECT is_manager_or_above() AS is_manager_or_above) OR (( SELECT is_owner_or_admin() AS is_owner_or_admin) OR (processing_store_id = ANY (( SELECT current_user_store_ids() AS current_user_store_ids)::uuid[])))))',
    '((( SELECT current_user_role() AS current_user_role) IS DISTINCT FROM ''inventory_manager''::user_role) AND ((current_user_role() IS NOT NULL) AND user_has_store_access(store_id)))',
    '((( SELECT current_user_role() AS current_user_role) IS DISTINCT FROM ''inventory_manager''::user_role) AND (( SELECT is_manager_or_above() AS is_manager_or_above) OR (store_id = ANY (( SELECT current_user_store_ids() AS current_user_store_ids)::uuid[])) OR (source_store_id = ANY (( SELECT current_user_store_ids() AS current_user_store_ids)::uuid[]))))',
    '((( SELECT current_user_role() AS current_user_role) IS DISTINCT FROM ''inventory_manager''::user_role) AND (( SELECT current_user_role() AS current_user_role) IS NOT NULL))',
    '((( SELECT current_user_role() AS current_user_role) IS DISTINCT FROM ''inventory_manager''::user_role) AND (( SELECT is_manager_or_above() AS is_manager_or_above) OR (store_id = ANY (( SELECT current_user_store_ids() AS current_user_store_ids)::uuid[])) OR (source_store_id = ANY (( SELECT current_user_store_ids() AS current_user_store_ids)::uuid[]))))',
    '((( SELECT current_user_role() AS current_user_role) IS DISTINCT FROM ''inventory_manager''::user_role) AND (( SELECT is_manager_or_above() AS is_manager_or_above) OR ((store_id IS NOT NULL) AND (( SELECT is_owner_or_admin() AS is_owner_or_admin) OR (store_id = ANY (( SELECT current_user_store_ids() AS current_user_store_ids)::uuid[])))) OR ((warehouse_id IS NOT NULL) AND ( SELECT can_manage_warehouse_stock() AS can_manage_warehouse_stock))))',
    '((( SELECT current_user_role() AS current_user_role) IS DISTINCT FROM ''inventory_manager''::user_role) AND (( SELECT current_user_role() AS current_user_role) IS NOT NULL))',
    '((( SELECT current_user_role() AS current_user_role) IS DISTINCT FROM ''inventory_manager''::user_role) AND (( SELECT is_manager_or_above() AS is_manager_or_above) OR (( SELECT is_owner_or_admin() AS is_owner_or_admin) OR (store_id = ANY (( SELECT current_user_store_ids() AS current_user_store_ids)::uuid[])))))',
    '((( SELECT current_user_role() AS current_user_role) IS DISTINCT FROM ''inventory_manager''::user_role) AND (( SELECT current_user_role() AS current_user_role) IS NOT NULL))',
    '((( SELECT current_user_role() AS current_user_role) IS DISTINCT FROM ''inventory_manager''::user_role) AND (( SELECT current_user_role() AS current_user_role) IS NOT NULL))',
    '((( SELECT current_user_role() AS current_user_role) IS DISTINCT FROM ''inventory_manager''::user_role) AND (( SELECT current_user_role() AS current_user_role) IS NOT NULL))',
    '((( SELECT current_user_role() AS current_user_role) IS DISTINCT FROM ''inventory_manager''::user_role) AND (( SELECT is_owner_or_admin() AS is_owner_or_admin) OR (store_id = ANY (( SELECT current_user_store_ids() AS current_user_store_ids)::uuid[]))))',
    '((( SELECT current_user_role() AS current_user_role) IS DISTINCT FROM ''inventory_manager''::user_role) AND (( SELECT current_user_role() AS current_user_role) IS NOT NULL))'];
  c_inv_tables constant text[] := array['invoices', 'invoice_items', 'invoice_payments'];
  c_trg_name constant text := 'no_invoicing_for_inventory_managers';
  c_new_sig constant text[] := array['inventory_manager_guard(text)', 'no_invoicing_for_inventory_managers()'];
  c_new_acl constant text[] := array['authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres', 'postgres=X/postgres'];
  c_new_md5 constant text[] := array[
    '6a2c8611ef58a1e6cdf4a91a0c662c9e',
    '54d7f917ffeb0a7916b8e3953249a3fb'];

  v_path text := current_setting('search_path');
  v_lock text := current_setting('lock_timeout');
  v_def text[] := array_fill(null::text, array[cardinality(c_sig)]);
  v_lang text; v_line text; d text; i int;
begin
  perform set_config('search_path', 'public', true);
  perform set_config('lock_timeout', '5s', true);

  -- 1. Checks: nothing is changed before all of them pass
  for i in 1 .. cardinality(c_sig) loop
    if to_regprocedure('public.' || c_sig[i]) is null then
      raise exception 'undo 540: public.% is missing. Nothing was changed.', c_sig[i]; end if;
    d := pg_get_functiondef(to_regprocedure('public.' || c_sig[i]));
    if md5(d) = c_before[i] then
      raise exception 'undo 540: public.% is already its version of before 540; 540 is not in. Nothing was changed.', c_sig[i]; end if;
    if md5(d) <> c_540[i] then
      raise exception 'undo 540: public.% is not 540''s version (md5 %). Nothing was changed.', c_sig[i], md5(d); end if;
    if (select coalesce(string_agg(x::text, ',' order by x::text), '')
          from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig[i])) is distinct from c_acl[i] then
      raise exception 'undo 540: the grants of public.% are not the tested ones. Nothing was changed.', c_sig[i]; end if;
    v_def[i] := d;
  end loop;
  for i in 1 .. cardinality(c_new_sig) loop
    if to_regprocedure('public.' || c_new_sig[i]) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || c_new_sig[i]))) <> c_new_md5[i] then
      raise exception 'undo 540: public.% is missing or not 540''s. Nothing was changed.', c_new_sig[i]; end if;
    if (select coalesce(string_agg(x::text, ',' order by x::text), '') from pg_proc p, unnest(p.proacl) x
         where p.oid = to_regprocedure('public.' || c_new_sig[i])) is distinct from c_new_acl[i] then
      raise exception 'undo 540: the grants of public.% are not 540''s. Nothing was changed.', c_new_sig[i]; end if;
  end loop;
  select string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text) into d
    from pg_proc p
   where p.pronamespace = 'public'::regnamespace and p.prokind = 'f'
     and p.oid not in (select to_regprocedure('public.' || x) from unnest(c_sig || c_new_sig) x)
     and pg_get_functiondef(p.oid) ~ 'inventory_manager_guard|no_invoicing_for_inventory_managers';
  if d is not null then
    raise exception 'undo 540: 540''s functions are also used by %. Nothing was changed.', d; end if;
  if (select count(*) from pg_trigger t where t.tgname = c_trg_name and not t.tgisinternal) <> cardinality(c_inv_tables)
     or (select count(*) from pg_trigger t join unnest(c_inv_tables) x on t.tgrelid = to_regclass('public.' || x)
          where t.tgname = c_trg_name and t.tgenabled = 'O'
            and pg_get_triggerdef(t.oid) = format('CREATE TRIGGER %s BEFORE INSERT OR DELETE OR UPDATE ON public.%s FOR EACH STATEMENT EXECUTE FUNCTION no_invoicing_for_inventory_managers()', c_trg_name, x))
        <> cardinality(c_inv_tables) then
    raise exception 'undo 540: the triggers % are not 540''s (each enabled, on its table). Nothing was changed.', c_trg_name; end if;
  for i in 1 .. cardinality(c_pol_table) loop
    if (select pg_get_expr(p.polqual, p.polrelid) from pg_policy p
         where p.polrelid = to_regclass('public.' || c_pol_table[i]) and p.polname = c_pol_name[i]) is distinct from c_pol_540[i] then
      raise exception 'undo 540: the read rule of public.% is not 540''s. Nothing was changed.', c_pol_table[i]; end if;
  end loop;
  for i in reverse cardinality(c_fn) .. 1 loop
    if (length(v_def[c_fn[i]]) - length(replace(v_def[c_fn[i]], c_new[i], ''))) / length(c_new[i]) <> 1 then
      raise exception 'undo 540: 540''s text % is not found exactly once in public.%. Nothing was changed.', i, c_sig[c_fn[i]]; end if;
    v_def[c_fn[i]] := replace(v_def[c_fn[i]], c_new[i], c_anchor[i]);
  end loop;
  for i in 1 .. cardinality(c_sig) loop
    if c_kind[i] is not null then
      select l.lanname into v_lang from pg_proc p join pg_language l on l.oid = p.prolang where p.oid = to_regprocedure('public.' || c_sig[i]);
      v_line := format(case when v_lang = 'plpgsql' then c_guard_pl else c_guard_sql end, c_kind[i]);
      if (length(v_def[i]) - length(replace(v_def[i], v_line, ''))) / length(v_line) <> 1 then
        raise exception 'undo 540: the guard line is not found exactly once in public.%. Nothing was changed.', c_sig[i]; end if;
      v_def[i] := replace(v_def[i], v_line, '');
    end if;
    if md5(v_def[i]) <> c_before[i] then
      raise exception 'undo 540: public.% without 540''s text is not its version of before 540 (md5 %). Nothing was changed.', c_sig[i], md5(v_def[i]); end if;
  end loop;

  -- 2. Put back (the functions first: they call the guard)
  for i in 1 .. cardinality(c_sig) loop
    execute v_def[i];
  end loop;
  for i in 1 .. cardinality(c_pol_table) loop
    execute format('alter policy %I on public.%I using (%s)', c_pol_name[i], c_pol_table[i], c_pol_before[i]);
  end loop;
  for i in 1 .. cardinality(c_inv_tables) loop
    execute format('drop trigger %I on public.%I', c_trg_name, c_inv_tables[i]);
  end loop;
  execute 'drop function public.no_invoicing_for_inventory_managers()';
  execute 'drop function public.inventory_manager_guard(text)';

  -- 3. Checks after
  for i in 1 .. cardinality(c_sig) loop
    if md5(pg_get_functiondef(to_regprocedure('public.' || c_sig[i]))) <> c_before[i]
       or (select coalesce(string_agg(x::text, ',' order by x::text), '')
             from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig[i])) is distinct from c_acl[i] then
      raise exception 'undo 540: public.% is not as before 540 after putting it back', c_sig[i]; end if;
  end loop;
  for i in 1 .. cardinality(c_pol_table) loop
    if (select pg_get_expr(p.polqual, p.polrelid) from pg_policy p
         where p.polrelid = to_regclass('public.' || c_pol_table[i]) and p.polname = c_pol_name[i]) is distinct from c_pol_before[i] then
      raise exception 'undo 540: the read rule of public.% is not as before 540 after putting it back', c_pol_table[i]; end if;
  end loop;

  perform set_config('lock_timeout', v_lock, true);
  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $undo$;
