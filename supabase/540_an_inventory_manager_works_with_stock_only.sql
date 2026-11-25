-- 540_an_inventory_manager_works_with_stock_only.sql
--
-- AN INVENTORY MANAGER WORKS WITH STOCK ONLY: NO INVOICES, NO CUSTOMERS' NAMES OR PHONES, NO
-- CUSTOMER BENEFIT RECORDS, NO RENTALS OR SPECIAL SALES, AND NO LENDING TO OR TAKING BACK FROM
-- CUSTOMERS
--
--   From the security audit of 17 Nov 2026 (finding M13, its Inventory Manager part). The BEFORE
--   md5s and the relied-on md5s below are those of production after 539 (function fingerprint
--   264a99c42f54d6560781e6cb8a6e6519/1460; 539's own AFTER md5s are pinned here). If production
--   differs when this is applied, it refuses and changes nothing. It needs 539.
--   (The number 540 is this file's name and its errors' prefix; if it changes at commit, change it
--   there, in the 540 comments it writes into the functions below (and so their AFTER md5s, also in
--   scripts/customers/undo-540.sql and in the suites that know them), and in the name and path of
--   its suite.)
--
-- GO-LIVE: in the same window as 539, after it; the pages of 540 first (they hide what an
--   Inventory Manager no longer reaches, and work before and after 540). None exist on production.
--
-- WHAT WAS WRONG
--
--   539 closed the customer list to an Inventory Manager, but an Inventory Manager assigned to a
--   store still makes, corrects, pays, hands over and deletes that store's invoices (New Invoice,
--   corrections, settlement, handover, invoice requests, split package and bundle invoices,
--   exchanges, therapy claims, each refusing them only for FOC or not at all), reads the store's
--   invoices and the functions behind the Invoices, Exchanges and Therapy pages (each with the
--   customer's name, some with phones: invoice_list_page, report_pricing, report_discounts,
--   invoice_display_names, preview_invoice_correction, exchange_original_context,
--   therapy_customer_detail for any customer by id, customer_overview, the affiliate directory,
--   and others), activates and reschedules customers' therapy, writes the print and send log, and
--   lends stock to customers and takes it back, reading every borrower's name and phone.
--
-- THE RULE (the user, 25 Nov 2026: "Stock only", "No lending by IM"; 26 Nov 2026: "Close them too")
--
--   An Inventory Manager may not create, change, pay, hand over or read invoices, and sees no
--   customer's name or phone anywhere. They keep stock, transfers, warehouse work, TikTok imports
--   of their own stores (521) and the Dashboard's sales totals (aggregates, no customer data).
--   Only an Owner, a Manager or Staff lends stock to and takes it back from customers, at a store
--   or a warehouse; an Inventory Manager sees loans without the borrower's name or phone. A loan's
--   stock movement notes give the loan number only ("LOAN-000002 lent (Trial), due back 2 Dec
--   2026"; "LOAN-000002 returned"), for everyone; the borrower stays on the loan. An Inventory
--   Manager reads no customer benefit record at all (packages and bundles sold and split, credit
--   given on special sales, purchased and earned therapy and its sessions, vouchers held, claimed
--   and redeemed, affiliates), nor rentals or special sales.
--
-- WHAT THIS DOES (every refusal is errcode 42501, in the words the pages show)
--
--   * A helper only postgres can call, inventory_manager_guard(what): for an Inventory Manager it
--     refuses with "An Inventory Manager does not make or change invoices." (what = invoice),
--     "An Inventory Manager does not lend stock or take it back." (loan), or "An Inventory Manager
--     works with stock only." (stock); everyone else, the secret key and the server's own work (no
--     login: cron, website orders, event VIP invoices) pass.
--   * It runs first in 66 functions (the list below, c_sig with a kind), which are otherwise word
--     for word as before: in a plpgsql function the line after the first "begin" that ends a line,
--     in an sql function the first statement:
--       invoice: create_invoice_with_details, create_split_credit_package_invoices,
--         create_split_premium_bundle_invoices, create_exchange_with_details, correct_invoice,
--         delete_invoice, record_invoice_handover, record_invoice_settlement,
--         request_invoice_action_v2, set_invoice_instalment_label, claim_entitlement_vouchers,
--         claim_purchased_therapy, preview_invoice_correction;
--       loan: lend_stock, return_stock_loan;
--       stock: every other signed-in function that reads customers' names or phones or invoice
--         rows and answered an Inventory Manager (the Invoices, Exchanges, Therapy, Events and
--         Affiliates pages' functions, customer_overview, customer_match_candidates, the
--         reports report_pricing, report_discounts, report_exchange_invoices, and the therapy
--         actions activate_purchased_therapy, choose_therapy_benefit, reschedule_purchased_therapy,
--         the print and send log record_document_printed and record_document_send, and the four
--         functions of a customer's therapy that run as their caller: customer_therapy_session_balance,
--         customer_therapy_voucher_rights, therapy_customer_entitlements,
--         therapy_customer_service_summary). Because those four run as the caller, the guard may be
--         called by signed-in logins and the service role; it answers nothing to anyone but an
--         Inventory Manager.
--   * Two functions keep answering an Inventory Manager without names: stock_loan_json (the stock
--     pages' loans: no borrower, no borrower_phone) and report_foc_lines (the Dashboard's FOC
--     totals: customer_name empty). stock_loan_access is unchanged: its "can act" also allows
--     Record use, which an Inventory Manager keeps; lend_stock and return_stock_loan refuse them
--     with their own guard, and the pages offer them neither.
--   * lend_stock and return_stock_loan write the loan number, not the borrower, in new stock
--     movement notes.
--   * A trigger before each statement that inserts, updates or deletes invoices, invoice lines or
--     invoice payments (no_invoicing_for_inventory_managers) refuses an Inventory Manager with the
--     invoice sentence, by any route (also one the list above does not name).
--   * The read rules of 24 tables leave an Inventory Manager out ("is distinct from
--     inventory_manager" and the rule as before): invoices (and so the 22 rules that look into
--     invoices, invoice_handover_lines and the others), invoice_handovers,
--     invoice_voucher_movements, product_exchanges (and so its three child tables),
--     therapy_entitlement_invoices, document_sends (the print and send log), stock_loans (and so
--     stock_loan_lines and stock_loan_events); the customer benefit records (the user, 26 Nov
--     2026: "Close them too"): credit_package_sales, credit_package_split_allocations,
--     premium_bundle_sales, premium_bundle_split_allocations, special_credit_allocations,
--     purchased_therapy_entitlements, therapy_entitlements, therapy_expiry_adjustments,
--     therapy_qualification_topups, therapy_voucher_issues, customer_therapy_sessions,
--     customer_reward_vouchers, voucher_claims, voucher_redemptions, customer_affiliates; and
--     rentals and special_sales (a customer id and the staff's free text; no page an Inventory
--     Manager opens reads them, and the functions their stock work runs are definers).
--
-- WHAT STAYS
--
--   * Owners, Admins, Managers and Staff: every function and rule answers them exactly as before.
--   * An Inventory Manager's stock work, as the suite runs it for them: warehouse_stock_in,
--     request_inventory_adjustments, record_stock_uses, create_transfer_request, save_product,
--     stage_tiktok_orders, stock_history_page, the Dashboard (dashboard_sales,
--     dashboard_sales_by_store, dashboard_alerts_summary, transfer_receipt_alerts,
--     tiktok_negative_stock_alerts, daily_payments_by_method), invoice_sales_ledger,
--     report_foc_lines (no name) and stock_loans_at (no borrower). None of it reads the closed
--     tables as the caller.
--   * invoice_sales_ledger() stays open to every staff role: the Dashboard's sales totals and the
--     Reports read it; it gives invoice ids, dates and amounts, no customer data, and with invoices
--     closed an id leads nowhere for an Inventory Manager.
--   * Pure helpers that read no rows (invoice_date_parse, invoice_no_sortkey and the like,
--     ads_normalize_phone, plan_invoice_date_recovery) and functions that already refuse an
--     Inventory Manager by their own role test (refunds, reopening, corrections of payments, FOC,
--     the website orders, the event registrations and others): as they are.
--   * Old stock movement notes keep the borrower's name; Stock History shows them as before.
--   * The Audit Log's stock_lent entry keeps the borrower (Owners, Admins and Managers read it).
--
-- UNDO
--
--   scripts/customers/undo-540.sql (it refuses unless every function, rule and trigger here is
--   exactly 540's and nothing else calls the new functions): puts the 68 functions back exactly
--   as they were, the 24 read rules as they were, and drops the three triggers and the two new
--   functions. Run it before scripts/customers/undo-539.sql. A later migration changing any of
--   these must pin 540's AFTER md5.
--
-- NO SELF-TEST INSIDE; the suite is scripts/customers/tests/inventory-manager-stock-only-540.sql.
--
-- One transaction with its history row, by the usual wrapper; nothing else is written.

do $mig$
declare
  -- Functions 540 relies on, as tested: the role, staff and store tests its rules and the guard use;
  -- the sales ledger and the loans list it keeps open; and 539's functions, AFTER (540 builds on 539).
  c_relied constant text[] := array[
    'current_user_role()',
    'require_active_staff(text[])',
    'user_has_store_access(uuid)',
    'can_manage_warehouse_stock()',
    'is_manager_or_above()',
    'is_owner_or_admin()',
    'current_user_store_ids()',
    'invoice_sales_ledger()',
    'stock_loans_at(text,uuid,boolean)',
    'stock_loan_access(text,uuid,boolean)',
    'customer_list_guard(integer)',
    'export_customers(text,text,text,text,date,date,date,date)',
    'my_profile_contact_details()',
    'search_customers(text,text,integer,integer,text,date,date)',
    'therapy_customer_summary(text,integer,integer,boolean)',
    'customer_survey_overview(text,text,integer,integer)',
    'active_affiliates_for_picker()',
    'user_admin_list()'];
  c_relied_md5 constant text[] := array[
    '519b0a33a3548f970c5d585b6e76a389',
    '877b3aa74cea559881979bb161c450e2',
    '708992afaa6c3951f6329239b742987c',
    '0fa45b2379faaf6c32ab5429b5b0792b',
    'e87f6da4a7284374f0e2bc5b55c502be',
    '9ddf58d83655a349abd2e3a2845ebb09',
    '54191b973c31654b903d48bea01ce533',
    '6278b7ac91ebbd2ae96a7e2182a29f33',
    '4d40d09d2263c304f8de7ddc9686d72d',
    '09f68356afdabb88cade05af7859e158',
    'de5cfaa12b667a4df0d45721b9531141',
    '1d0eb73a09a49a939f353582844c1fd5',
    '6ae2834b13b1ab52653da4cf342b99df',
    '25f9a33395ad17f7d6b8f63252bd34ab',
    '93c046a23c15684aa88a67b2dd3f5c34',
    '42b98e0787c27efa66f4b32c0272c8dc',
    'a75fa8c401202112d4abf0b478b0e59a',
    'ab6167ddfea14ecc4b1140ce4221a0d4'];
  -- The functions patched: BEFORE, AFTER, grants (unchanged), and the guard each gets first
  -- (invoice, loan, stock; null: none, only its patches below).
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
  c_after constant text[] := array[
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
  -- The patches, each found exactly once in its function, after the guard is in.
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
  -- The guard's line in each function (plpgsql: after the first "begin" ending a line; sql: first).
  c_guard_pl constant text := '  perform public.inventory_manager_guard(%L);  -- 540 (security audit of 17 Nov 2026, M13; the user, 25 Nov 2026: "Stock only")' || E'\n';
  c_guard_sql constant text := '  select public.inventory_manager_guard(%L);  -- 540 (security audit of 17 Nov 2026, M13; the user, 25 Nov 2026: "Stock only")' || E'\n';
  -- The read rules an Inventory Manager is taken out of: before and after.
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
  c_pol_after constant text[] := array[
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
  -- The invoice tables the "No invoicing" trigger sits on.
  c_inv_tables constant text[] := array['invoices', 'invoice_items', 'invoice_payments'];
  c_trg_name constant text := 'no_invoicing_for_inventory_managers';
  -- The new functions: the guard for signed-in logins and the service role too (four of the
  -- functions that call it run as their caller; it answers nothing to anyone but an Inventory
  -- Manager), the trigger function postgres's alone.
  c_new_sig constant text[] := array['inventory_manager_guard(text)', 'no_invoicing_for_inventory_managers()'];
  c_new_acl constant text[] := array['authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres', 'postgres=X/postgres'];
  c_new_def constant text[] := array[
$d$CREATE OR REPLACE FUNCTION public.inventory_manager_guard(p_what text)
 RETURNS void
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  -- 540 (security audit of 17 Nov 2026, M13; the user, 25 Nov 2026: "Stock only", "No lending by
  -- IM"): run first by every function that makes or changes an invoice, lends or takes back stock,
  -- or shows customers, invoices or customer benefits. An Inventory Manager is refused; everyone
  -- else, the secret key and the server's own work (no login) pass.
  if public.current_user_role() = 'inventory_manager' then
    raise exception '%', case p_what
      when 'invoice' then 'An Inventory Manager does not make or change invoices.'
      when 'loan' then 'An Inventory Manager does not lend stock or take it back.'
      else 'An Inventory Manager works with stock only.' end
      using errcode = '42501';
  end if;
end
$function$
$d$,
$d$CREATE OR REPLACE FUNCTION public.no_invoicing_for_inventory_managers()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  -- 540 (security audit of 17 Nov 2026, M13; the user, 25 Nov 2026: "Stock only"): before each
  -- statement that writes invoices, invoice lines or invoice payments, by any route. An Inventory
  -- Manager makes or changes no invoice; everyone else, and the server's own work, as before.
  perform public.inventory_manager_guard('invoice');
  return null;
end
$function$
$d$];
  c_new_md5 constant text[] := array[
    '6a2c8611ef58a1e6cdf4a91a0c662c9e',
    '54d7f917ffeb0a7916b8e3953249a3fb'];

  v_path text := current_setting('search_path');
  v_lock text := current_setting('lock_timeout');
  v_def text[] := array_fill(null::text, array[cardinality(c_sig)]);
  v_done int := 0; v_new_done int := 0; v_pol_done int := 0; v_trg_done int; v_bad text := '';
  v_lang text; v_line text; d text; i int;
begin
  -- Definitions are read and compared with public alone on the search path.
  perform set_config('search_path', 'public', true);
  -- A busy function or table waits 5 seconds at most, then this refuses whole.
  perform set_config('lock_timeout', '5s', true);

  -- 1. Checks: nothing is changed before all of them pass
  for i in 1 .. cardinality(c_relied) loop
    if to_regprocedure('public.' || c_relied[i]) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i]))) <> c_relied_md5[i] then
      raise exception '540: public.% is missing or not the version this was tested against (539 must be in). Re-read it and re-test before applying.', c_relied[i];
    end if;
  end loop;
  for i in 1 .. cardinality(c_sig) loop
    if to_regprocedure('public.' || c_sig[i]) is null then raise exception '540: public.% is missing', c_sig[i]; end if;
    d := pg_get_functiondef(to_regprocedure('public.' || c_sig[i]));
    if (select coalesce(string_agg(x::text, ',' order by x::text), '')
          from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig[i])) is distinct from c_acl[i] then
      raise exception '540: the grants of public.% are not the tested ones. Re-read them before applying.', c_sig[i]; end if;
    if md5(d) = c_after[i] then
      v_done := v_done + 1;
    elsif md5(d) = c_before[i] then
      v_def[i] := d;
    else
      raise exception '540: public.% is not the version this was tested against (md5 %). Re-read it and re-test before applying.', c_sig[i], md5(d);
    end if;
  end loop;
  for i in 1 .. cardinality(c_pol_table) loop
    if (select count(*) from pg_policy p where p.polrelid = to_regclass('public.' || c_pol_table[i]) and p.polcmd in ('r', '*')) <> 1
       or not exists (select 1 from pg_policy p where p.polrelid = to_regclass('public.' || c_pol_table[i]) and p.polname = c_pol_name[i]
                       and p.polcmd = 'r' and p.polpermissive and p.polroles = array['authenticated'::regrole::oid]
                       and pg_get_expr(p.polqual, p.polrelid) in (c_pol_before[i], c_pol_after[i])) then
      raise exception '540: the read rule of public.% is not the one this was tested against. Re-read it before applying.', c_pol_table[i]; end if;
    if (select pg_get_expr(p.polqual, p.polrelid) from pg_policy p
         where p.polrelid = to_regclass('public.' || c_pol_table[i]) and p.polname = c_pol_name[i]) = c_pol_after[i] then
      v_pol_done := v_pol_done + 1; end if;
  end loop;
  for i in 1 .. cardinality(c_new_sig) loop
    if to_regprocedure('public.' || c_new_sig[i]) is not null then
      if md5(pg_get_functiondef(to_regprocedure('public.' || c_new_sig[i]))) <> c_new_md5[i] then
        raise exception '540: a function public.% is there, but not 540''s. Re-read it before applying.', c_new_sig[i]; end if;
      v_new_done := v_new_done + 1;
    end if;
  end loop;
  if exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace
              and p.proname in ('inventory_manager_guard', 'no_invoicing_for_inventory_managers')
              and p.oid::regprocedure::text not in (select x from unnest(c_new_sig) x)) then
    raise exception '540: another function of one of 540''s names is there. Re-read it before applying.'; end if;
  select count(*) into v_trg_done from pg_trigger t where t.tgname = c_trg_name and not t.tgisinternal;
  if v_trg_done not in (0, cardinality(c_inv_tables)) then
    raise exception '540: a trigger % is there, but not 540''s. Re-read it before applying.', c_trg_name; end if;
  if v_done = cardinality(c_sig) and v_pol_done = cardinality(c_pol_table) and v_new_done = cardinality(c_new_sig) and v_trg_done > 0 then
    raise exception '540 is already in on this database; nothing was changed.'; end if;
  if v_done > 0 or v_pol_done > 0 or v_new_done > 0 or v_trg_done > 0 then
    raise exception '540: only part of it is in on this database (% of % functions patched, % of % read rules, % of % new functions, % of % triggers). Re-read them before applying; nothing was changed.',
      v_done, cardinality(c_sig), v_pol_done, cardinality(c_pol_table), v_new_done, cardinality(c_new_sig), v_trg_done, cardinality(c_inv_tables); end if;
  -- The guard first, then the patches; each result exactly the tested text.
  for i in 1 .. cardinality(c_sig) loop
    if c_kind[i] is not null then
      select l.lanname into v_lang from pg_proc p join pg_language l on l.oid = p.prolang where p.oid = to_regprocedure('public.' || c_sig[i]);
      if v_lang = 'plpgsql' then
        if v_def[i] !~ '\mbegin\n' then raise exception '540: public.% has no "begin" ending a line', c_sig[i]; end if;
        v_def[i] := regexp_replace(v_def[i], '\mbegin\n', 'begin' || E'\n' || replace(format(c_guard_pl, c_kind[i]), '\', '\\'));
      elsif v_lang = 'sql' then
        if (length(v_def[i]) - length(replace(v_def[i], 'AS $function$' || E'\n', ''))) / 14 <> 1 then
          raise exception '540: public.% has no single "AS $function$"', c_sig[i]; end if;
        v_def[i] := replace(v_def[i], 'AS $function$' || E'\n', 'AS $function$' || E'\n' || format(c_guard_sql, c_kind[i]));
      else
        raise exception '540: public.% is in %, not plpgsql or sql', c_sig[i], v_lang;
      end if;
    end if;
  end loop;
  for i in 1 .. cardinality(c_fn) loop
    if (length(v_def[c_fn[i]]) - length(replace(v_def[c_fn[i]], c_anchor[i], ''))) / length(c_anchor[i]) <> 1 then
      raise exception '540: patch % does not find its text exactly once in public.%', i, c_sig[c_fn[i]]; end if;
    v_def[c_fn[i]] := replace(v_def[c_fn[i]], c_anchor[i], c_new[i]);
  end loop;
  for i in 1 .. cardinality(c_sig) loop
    if md5(v_def[i]) <> c_after[i] then v_bad := v_bad || format(E'\n%s=%s', c_sig[i], md5(v_def[i])); end if;
  end loop;
  for i in 1 .. cardinality(c_new_sig) loop
    if md5(c_new_def[i]) <> c_new_md5[i] then v_bad := v_bad || format(E'\nnew:%s=%s', i, md5(c_new_def[i])); end if;
  end loop;
  if v_bad <> '' then
    raise exception '540: the patched text is not the tested one:%', v_bad; end if;

  -- 2. Install: the new functions first (the guard is called by everything below)
  for i in 1 .. cardinality(c_new_sig) loop
    execute c_new_def[i];
    execute format('revoke all on function public.%s from public, anon, authenticated, service_role', c_new_sig[i]);
    if c_new_acl[i] <> 'postgres=X/postgres' then
      execute format('grant execute on function public.%s to authenticated, service_role', c_new_sig[i]);
    end if;
  end loop;
  for i in 1 .. cardinality(c_sig) loop
    execute v_def[i];
  end loop;
  for i in 1 .. cardinality(c_pol_table) loop
    execute format('alter policy %I on public.%I using (((select public.current_user_role()) is distinct from ''inventory_manager''::public.user_role) and (%s))',
                   c_pol_name[i], c_pol_table[i], c_pol_before[i]);
  end loop;
  for i in 1 .. cardinality(c_inv_tables) loop
    execute format('create trigger %I before insert or update or delete on public.%I for each statement '
                   'execute function public.no_invoicing_for_inventory_managers()', c_trg_name, c_inv_tables[i]);
  end loop;

  -- 3. Checks after installing
  for i in 1 .. cardinality(c_sig) loop
    if md5(pg_get_functiondef(to_regprocedure('public.' || c_sig[i]))) <> c_after[i] then
      raise exception '540: public.% was installed with an md5 other than the tested one', c_sig[i]; end if;
    if (select coalesce(string_agg(x::text, ',' order by x::text), '')
          from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig[i])) is distinct from c_acl[i] then
      raise exception '540: the grants of public.% changed', c_sig[i]; end if;
  end loop;
  for i in 1 .. cardinality(c_new_sig) loop
    if md5(pg_get_functiondef(to_regprocedure('public.' || c_new_sig[i]))) <> c_new_md5[i]
       or (select coalesce(string_agg(x::text, ',' order by x::text), '') from pg_proc p, unnest(p.proacl) x
            where p.oid = to_regprocedure('public.' || c_new_sig[i])) is distinct from c_new_acl[i]
       or has_function_privilege('anon', to_regprocedure('public.' || c_new_sig[i]), 'execute') then
      raise exception '540: public.% was made other than tested', c_new_sig[i]; end if;
  end loop;
  for i in 1 .. cardinality(c_pol_table) loop
    if (select pg_get_expr(p.polqual, p.polrelid) from pg_policy p
         where p.polrelid = to_regclass('public.' || c_pol_table[i]) and p.polname = c_pol_name[i]) is distinct from c_pol_after[i] then
      v_bad := v_bad || format(E'\npol:%s=%s', c_pol_table[i], (select pg_get_expr(p.polqual, p.polrelid) from pg_policy p
         where p.polrelid = to_regclass('public.' || c_pol_table[i]) and p.polname = c_pol_name[i])); end if;
  end loop;
  if v_bad <> '' then raise exception '540: the read rules are not the tested ones:%', v_bad; end if;
  if (select count(*) from pg_trigger t join unnest(c_inv_tables) x on t.tgrelid = to_regclass('public.' || x)
       where t.tgname = c_trg_name and t.tgenabled = 'O'
         and pg_get_triggerdef(t.oid) = format('CREATE TRIGGER %s BEFORE INSERT OR DELETE OR UPDATE ON public.%s FOR EACH STATEMENT EXECUTE FUNCTION no_invoicing_for_inventory_managers()',
                                               c_trg_name, x)) <> cardinality(c_inv_tables) then
    raise exception '540: the triggers % are not the tested ones after installing', c_trg_name; end if;
  for i in 1 .. cardinality(c_relied) loop
    if md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i]))) <> c_relied_md5[i] then
      raise exception '540: public.% changed', c_relied[i]; end if;
  end loop;

  perform set_config('lock_timeout', v_lock, true);
  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $mig$;
