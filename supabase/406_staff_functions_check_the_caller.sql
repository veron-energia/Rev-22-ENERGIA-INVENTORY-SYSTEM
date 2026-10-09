-- 406_staff_functions_check_the_caller.sql
--
-- WHAT WAS WRONG (audit of 8 Oct 2026; access inventory of 9 Oct 2026)
--
--   The database took every signed-in login for a member of staff. That has
--   not been true since affiliates got logins of their own (155): every
--   affiliate signs in, anyone could create a login at /affiliate/join with
--   only an email address (paused by 405), and a deactivated employee keeps
--   their password. On 9 Oct 2026 production had 68 logins and 8 staff
--   profiles (one inactive); 45 of the logins are affiliates and 15 neither.
--
--   The table rules kept those logins out of most tables, but the staff pages
--   read through server functions that run with the owner's rights, and 48
--   of them never asked who was calling. The repository is public, so their
--   names are known. Called with the app's public key as an affiliate login
--   with no staff profile (production, read-only, counts only):
--     * customer_survey_overview returned every customer, 12,936, each with a
--       phone, in pages of any size;
--     * consultant_notes_for(null, null) returned all 276 consultant notes,
--       with acidity, health goals, condition and recommendation;
--     * therapy_customer_summary and therapy_customer_detail returned the
--       therapy customers with phones and any customer's entitlements;
--     * customer_overview, customer_profile_stats and
--       customer_purchase_timeline returned any customer's invoices, spend,
--       refunds and therapy;
--     * active_affiliates_for_picker returned all 46 affiliates with phones,
--       affiliate_legacy_day_summary other affiliates' qualifying sales,
--       store_commission_staff staff names, special_docs_awaiting_fulfilment
--       customers' special orders waiting for release, and
--       dashboard_alerts_summary, dashboard_summary, report_customer_sources
--       and tiktok_negative_stock_alerts business counts and the FOC value;
--     * invoice_therapy_summary, invoice_bill_to_source and five more
--       answered for any invoice id.
--   Some of them also WROTE for any login:
--     * upsert_consultant_survey created a survey, or overwrote a customer's
--       consultant findings and health declarations. A declaration counts as
--       a centre visit on the day it is written, so an affiliate could make
--       the friends they referred "visit" during the October promotion;
--     * add_customer_remark added a remark to any customer, under any survey;
--     * pay_special_with_credit spent any customer's wallet credit;
--     * resolve_tiktok_physical_return restocked: its gate tests a role that
--       is null for such a login, and a null test skips the raise;
--     * record_document_send wrote the send log;
--     * write_audit wrote any audit entry a browser sent (table, record,
--       action, before and after), so the Audit Log could be forged (X-7).
--   auth_email_user_state, auth_email_reserve and auth_email_record_outcome,
--   which 339 granted back to signed-in logins, told any login whether an
--   email address has an Energia login and let it fill the rate-limit tables
--   (X-8). Three staff-commission rebase diagnostics have had no caller since
--   3 Oct and answered any login (X-3).
--
--   current_user_role(), which 47 policies and 66 functions read as "is
--   staff", also returned the role of inactive, pending and cancelled
--   profiles (X-5): a deactivated employee kept every table rule's access.
--   dashboard_credit_by_store and dashboard_credit_spend read profiles.role
--   themselves, with no "active" test either. Three more let a person act on
--   their own records before asking whether they still work here (review of
--   9 Oct): cancel_transfer_request cancelled a deactivated employee's own
--   pending transfer request, return_stock_loan replayed their earlier
--   take-back and returned the loan, and my_assigned_store_id() still named
--   their store.
--
-- THE RULES (the Owner approved the fix on 9 Oct 2026, "Security (urgent)")
--
--   1. A staff page's server function answers active staff only: a profile
--      that is active, not deleted and accepted, as user_admin_role() has
--      it. Anything else is refused with SQLSTATE 42501 before the function
--      reads or writes anything.
--   2. Where a page is for some roles only, its functions are too, with the
--      role set the page itself uses:
--        Owner and Manager (isOwnerOrManager): the customer profile's figures
--          and purchase history, customer remarks, the Special page (its
--          queue, stock and wallet payments), the Qualification tab's day
--          summary;
--        Owner, Admin and Manager (isManagerOrAbove): the dashboard's summary
--          cards, the therapy service catalogue;
--        every role but Inventory Manager: consultant notes and the
--          consultant survey, as health_survey_detail and the survey files
--          already have it;
--        every staff role: the others.
--      customer_profile_stats and dashboard_summary went to every role but
--      their figures were drawn for those roles only, and the pages treat a
--      refusal as "no figures", so no page changes for a role that can open
--      it.
--   3. One invoice's details answer staff of that invoice's store, as the
--      invoice list does (user_has_store_access: Owners and Admins every
--      store).
--   4. The server is not a login. The service role (website orders, the Edge
--      Functions), pg_cron and migrations carry neither the anon nor the
--      authenticated role and pass, so payments, website orders, triggers and
--      the cron jobs that reach these functions keep working.
--   5. A function no page or Edge Function calls with a login is not an
--      endpoint (339).
--   6. The consultant's findings (acidity, health goals, condition,
--      recommendation) are written by an Owner or Manager only, as by
--      review_health_survey and add_consultant_note. A survey and a remark are
--      for a live customer only, and a remark's survey is that customer's.
--
-- WHAT THIS DOES
--
--   * require_active_staff(p_roles) (new; internal, the service role's alone,
--     339): rules 1, 2 and 4. Returns the caller's role, or null for the
--     server. require_store_access(p_store_id) (new; internal): rule 3 for a
--     store id, after require_active_staff.
--   * current_user_role() (replaced whole; grants kept): only an active,
--     accepted, not-deleted profile has a role (X-5), so the 47 policies and
--     66 functions that read it stop treating such a login as staff. It is
--     declared STABLE, as it is.
--   * 50 functions (patched; grants kept): their first statement is the
--     check. Every staff role: customer_survey_overview, customer_overview,
--     therapy_customer_summary, therapy_customer_detail,
--     active_affiliates_for_picker, store_commission_staff,
--     dashboard_alerts_summary, report_customer_sources,
--     tiktok_negative_stock_alerts, record_document_send,
--     resolve_tiktok_physical_return, dashboard_credit_by_store,
--     dashboard_credit_spend, claim_entitlement_vouchers,
--     claim_legacy_therapy, entitlement_voucher_state, active_foc_reasons,
--     bundle_line_components, exchange_ineligibility_reason,
--     legacy_reward_options, legacy_reward_options_diagnostic,
--     legacy_reward_voucher_options, legacy_setup_status,
--     credit_package_benefit_preview, premium_bundle_benefit_preview,
--     credit_packages_for_store, premium_bundles_for_store,
--     credit_package_effective_rules, promotion_original_total,
--     cancel_transfer_request, return_stock_loan. Owner and
--     Manager: customer_profile_stats, customer_purchase_timeline,
--     add_customer_remark, affiliate_legacy_day_summary,
--     special_docs_awaiting_fulfilment, special_product_availability,
--     products_available_as_special, pay_special_with_credit. Owner, Admin
--     and Manager: dashboard_summary, therapy_service_catalogue. Not
--     Inventory Manager: consultant_notes_for, upsert_consultant_survey.
--     The invoice's store: exchange_invoice_details, invoice_bill_to_source,
--     invoice_legacy_entitlements, invoice_revision_history,
--     invoice_therapy_summary, invoice_transferable_benefits; the store asked
--     about: legacy_qualification_diagnose.
--   * my_assigned_store_id() (patched; grants kept): names a store for an
--     active member of staff only. The functions that read it have already
--     found an active Staff role, so they answer as before.
--   * Beside the check: customer_survey_overview returns at most 200 rows a
--     page (the Surveys page asks for 50); consultant_notes_for answers for
--     one survey or one customer, never for both left out; add_customer_remark
--     refuses a deleted customer and a survey of another customer;
--     upsert_consultant_survey refuses a deleted customer, takes the
--     consultant's findings from an Owner or Manager only (the page sends
--     none), locks the customer's row so a second quick click finds the
--     first click's survey instead of failing on the one-survey rule, and
--     numbers a new survey by the Singapore date instead of the UTC one.
--   * record_document_printed(kind, id) (new; signed-in logins and the
--     service role): the audit row the invoice and exchange Print buttons
--     leave (invoice_printed, exchange_printed), written through write_audit
--     for a document the caller can see; the pages call it in place of
--     write_audit.
--   * Revoked from public, anon and authenticated, kept for the service role:
--     write_audit (41 server functions still write through it, as the
--     owner), auth_email_user_state, auth_email_reserve,
--     auth_email_record_outcome (the auth Edge Functions call them with the
--     service key), commission_outside_rebase_scope,
--     commission_totals_reconciliation, preview_commission_rebase_effect and
--     validate_bundle_voucher_selection (called only from other server
--     functions).
--   * The read rule on profiles ("read profiles") also lets a login read its
--     own row, so a deactivated employee is still told "Your account has been
--     deactivated" rather than "Account setup needed".
--
-- NOT CHANGED
--
--   * The five signed-out endpoints, the affiliate portal (affiliate_portal_*,
--     complete_affiliate_onboarding, the claim functions), the policy helpers
--     (is_owner_or_manager, user_has_store_access and the rest), write_audit_ex,
--     and every function's arguments, results and grants (but the revoked).
--   * The other 375 functions a login can call (besides the five signed-out
--     endpoints and current_user_role). The inventory of 9 Oct found each
--     already refuses a login with no staff profile: by its own role or store
--     test, by reading current_user_role(), or as a SECURITY INVOKER function
--     under the table rules. scripts/permissions/tests/
--     staff-only-functions.sql calls every one of them as such logins, with
--     nulls and with the fixture's own ids and names; one it does not name
--     (by its full signature) must refuse, and none may hand over the
--     fixture's data or write anything.
--   * Tables, storage and the rest of the profile rules: 407. No row.
--
-- SAFETY
--
--   Apart from the lock timeout this is one DO block, so it is atomic. Every
--   check is made and every new text built before anything is installed:
--     * each patched function is the production version read on 9 Oct 2026
--       after 405 (BEFORE), or already this migration's (AFTER), which is left
--       alone, so a re-run changes nothing;
--     * the new functions are missing or already this version;
--     * each revoked function and each helper relied on is the version read
--       on 9 Oct 2026; no other function takes any of these names (the API
--       picks an overload by name);
--     * every anchor occurs exactly once, and each text built has its AFTER
--       md5 before it is installed.
--   The texts are executed as CREATE OR REPLACE with the same arguments and
--   result types, which keeps owner and grants. The definitions are read and
--   compared with the search path set to public. Afterwards: every function
--   has its AFTER md5 and the grants it had; the two checks are the service
--   role's alone; record_document_printed is signed-in logins' and the
--   service role's, not callable signed out; the revoked are callable by no
--   client role. Then, switching role: a signed-in login with no profile is
--   refused by customer_survey_overview, consultant_notes_for,
--   active_affiliates_for_picker, record_document_send,
--   upsert_consultant_survey, write_audit and auth_email_user_state, and has
--   no current_user_role(); the service role still reads
--   credit_package_effective_rules and store_commission_staff; and an active
--   Owner, when there is one, still has a role and reads a page of the survey
--   list and the dashboard summary. Nothing is printed and no row changes.
--
-- BEFORE (production, 9 Oct 2026, after 405; md5 of pg_get_functiondef):
--   patched
--   active_affiliates_for_picker()                            916a481a909edb09147d3caead51305a
--   active_foc_reasons()                                      673f6f4b27299da95ecfdab5eba69612
--   add_customer_remark(uuid,text,text,uuid)                  2e9a0327fb1c66e9a56d1862a7aaf568
--   affiliate_legacy_day_summary(date)                        a5deac1fba5880636f0cda357dadab42
--   bundle_line_components(uuid)                              799461c5855df161cf48ea3eabf5a4cc
--   cancel_transfer_request(uuid)                             5f4d42e33c83bfab0b922474babecbb5
--   claim_entitlement_vouchers(uuid,jsonb,text)               a0215fa3aaaa162772fa6e4dd9ea08bd
--   claim_legacy_therapy(uuid,date,uuid,jsonb,text,text)      f14136078f691d743b6a0def4a874b09
--   consultant_notes_for(uuid,uuid)                           9902c96cf8295d11ab4e237dedc60f19
--   credit_package_benefit_preview(uuid,uuid)                 e0e5dd9571e42c1c2248bc0bc4fea8a9
--   credit_package_effective_rules(uuid)                      8daf32528ae969300ed4bdc9ba13f955
--   credit_packages_for_store(uuid,date)                      31a4a17f994467786e0cd3202324b578
--   customer_overview(uuid)                                   c2dfc1bd43e61699338598bda27e6303
--   customer_profile_stats(uuid)                              bca7226679aed8fd44ed9b646a7af27a
--   customer_purchase_timeline(uuid)                          fdf6a2c95663ccbac05d7276defdb5dc
--   customer_survey_overview(text,text,integer,integer)       b341a5207c6cd72082cc571f1a44b6cc
--   dashboard_alerts_summary()                                13122db6bf0b5c22ea2482e8d28a42af
--   dashboard_credit_by_store(text,date,date)                 98157ff3234002bbf0faad93ee746e99
--   dashboard_credit_spend(text,date,date,uuid)               4515b567863253ad3cf3e450852aaacf
--   dashboard_summary()                                       144fa049474bf7d2932cf5f9bac094be
--   entitlement_voucher_state(uuid)                           80264a4e7fa785b8dca628a41d0145b1
--   exchange_ineligibility_reason(uuid)                       605f70041cd659acbaed2c0347bdbc92
--   exchange_invoice_details(uuid)                            358c33245d0c0bd52e9b96f009b9687b
--   invoice_bill_to_source(uuid)                              d6fae8edb4b1930589c793ed61de8830
--   invoice_legacy_entitlements(uuid)                         f2db5293a473c1a26582519c80ec6dde
--   invoice_revision_history(uuid)                            6111514b5b8396d1304d43f14ae8cf69
--   invoice_therapy_summary(uuid)                             52ce8a657627bc919d1580fc6b316e18
--   invoice_transferable_benefits(uuid)                       53b7e5631c96fb56273c08354bf8442b
--   legacy_qualification_diagnose(uuid,uuid,date)             70221c452ec55d19f31ae443a984b1a3
--   legacy_reward_options(uuid)                               92a9255cc922d668f885888b208b4560
--   legacy_reward_options_diagnostic(uuid)                    743db28f35ff92291373f58703366cbb
--   legacy_reward_voucher_options(uuid)                       d4f3df259b63ee561837a3d7890c5f5f
--   legacy_setup_status()                                     e2f1a408b8f630fd29d870e1f7fd5326
--   my_assigned_store_id()                                    b4864f1257e48312c4a273f241f8c1c5
--   pay_special_with_credit(text,uuid,uuid,numeric,uuid)      dfbae74ac655ea4e711db90ea9adacfc
--   premium_bundle_benefit_preview(uuid,uuid)                 3e0de91e323105ef941c434d0bdeacdc
--   premium_bundles_for_store(uuid,date)                      0b8b5b2a16747e6a12c217098a78ff7e
--   products_available_as_special()                           8e76dcac282b039735ced84fd2707c93
--   promotion_original_total(uuid,uuid)                       9712b8d78d474896aac89081469afd30
--   record_document_send(text,text,text,uuid,uuid,text,text,text,text)
--                                                             d4b4aff765a161e58f31fda2d2e37ef8
--   report_customer_sources(date,date)                        1b54e0dd1ea7b215c396ca87c760555e
--   resolve_tiktok_physical_return(uuid,boolean,text,text)    844cf27fde0936e93f20b3a05ad8dfe7
--   return_stock_loan(uuid,jsonb,text,uuid)                   978c886b03ccae32d48de8bc78667975
--   special_docs_awaiting_fulfilment()                        ff0f89048581abdfac941fdf84e39514
--   special_product_availability(uuid)                        57d4d5e52f787dc71d957c4ba9276045
--   store_commission_staff(uuid)                              7aca1c0300eb821fa8b825761c211f98
--   therapy_customer_detail(uuid)                             fcbedaa5ef6f2f56c3271d3c6d6690ec
--   therapy_customer_summary(text,integer,integer,boolean)    6bb0f3b4b81882f51ee4f4e115391779
--   therapy_service_catalogue(uuid,boolean)                   d4bcd45afab45f2a63a18650c2b5412d
--   tiktok_negative_stock_alerts()                            7415c756855445f041c5a616de345573
--   upsert_consultant_survey(uuid,text,text,text,text,boolean,boolean,boolean,boolean,text,uuid)
--                                                             1389c4734bffe9b21dfbfad35a17c38a
--   current_user_role()                                       b134c4be5f2c9db31c41dc029689d2c2
--   revoked, text unchanged
--   write_audit(text,uuid,text,jsonb,jsonb)                   19cd6b07bdbb6c73c26fb8aa83d2463e
--   auth_email_user_state(text)                               2e95d18a8d08dac7d54f4e98c94b7998
--   auth_email_reserve(text,text,text)                        e391dd051d05f0661c7924f24e04a1b2
--   auth_email_record_outcome(uuid,text,text,text,integer,text)
--                                                             c0d13ae48f06851f2845d13adad03e60
--   commission_outside_rebase_scope()                         d91d28959dd66cfd91b1fd8522e9c724
--   commission_totals_reconciliation()                        5830555097c3e489dd9f2e799af9d87a
--   preview_commission_rebase_effect(date,date)               4aa9ebaf897a1c3aa97cac944a8180e4
--   validate_bundle_voucher_selection(uuid,uuid,jsonb)        16e707758a4d771c49c403ef8983570f
--   relied on, not changed
--   user_has_store_access(uuid)                               8c82c6bcb64f496c5a05a2b8dafa95f8
--   is_manager_or_above()                                     f12b9ed342070fa4defa30e4da2ba655
--   sg_today()                                                1c1289f18e24d8370e9a6364c9c06fca
--   write_audit_ex(text,uuid,text,jsonb,jsonb,text,text,uuid,text,text)
--                                                             c705c733e213a27f0dc32d54322cc855
--   user_admin_role()                                         6fe6c3202163ce80babdcf04fc28f76b
--   health_survey_detail(uuid)                                e04b50ad8507d77e9436e2a2a84766d1
--   new: require_active_staff(text[]), require_store_access(uuid),
--   record_document_printed(text,uuid) (missing)
-- AFTER (for later guards):
--   require_active_staff(text[])                              877b3aa74cea559881979bb161c450e2
--   require_store_access(uuid)                                f9332fd2f0092337d64501d8a647c23f
--   record_document_printed(text,uuid)                        b67386018227a05327874c57e2acb9d2
--   current_user_role()                                       519b0a33a3548f970c5d585b6e76a389
--   active_affiliates_for_picker()                            95316cbb02a3ecc6c078c8b877b14d6d
--   active_foc_reasons()                                      9d7d60ee289a56dfeccd6d2ed9c46732
--   add_customer_remark(uuid,text,text,uuid)                  cb073e29fb2de5ec92628a7220188be4
--   affiliate_legacy_day_summary(date)                        f0170fcb61ff1a40c07d532186669212
--   bundle_line_components(uuid)                              93ebc0e25991428c5e94a71879bbef41
--   cancel_transfer_request(uuid)                             b12baadcf077487a6c275877275c4750
--   claim_entitlement_vouchers(uuid,jsonb,text)               e6958c6052d3dd8d7ea3a175d614b5da
--   claim_legacy_therapy(uuid,date,uuid,jsonb,text,text)      3957f56f3ea9dc8df6789371a20add66
--   consultant_notes_for(uuid,uuid)                           4f894f72b4af092d7ddd1421b3ab8597
--   credit_package_benefit_preview(uuid,uuid)                 4a79692ddfb66374f352c9a6bf9fe565
--   credit_package_effective_rules(uuid)                      0b8e865eb1c56e15db885753ffe6f1ee
--   credit_packages_for_store(uuid,date)                      85df02046be2b8afc1fa9b685b37aca0
--   customer_overview(uuid)                                   74e9cddfb699ed78369ee4d01578116e
--   customer_profile_stats(uuid)                              67c5770c7bc0be83899e5fde593fc851
--   customer_purchase_timeline(uuid)                          cb21b1612cc04f5da2e5f07c46f81d0d
--   customer_survey_overview(text,text,integer,integer)       e84eb56b42505e2f8a34e6e7486cf6f9
--   dashboard_alerts_summary()                                c3a45ca21c315d5cd6bd1bf36108d905
--   dashboard_credit_by_store(text,date,date)                 fe25ab311d6e3655500dea66c07fa0f1
--   dashboard_credit_spend(text,date,date,uuid)               540ee810178c15f5c09a6b305bc4bd0d
--   dashboard_summary()                                       96ddc8f96a9bb00a222f11860d2ac221
--   entitlement_voucher_state(uuid)                           f8b6a3a4521e025ed2cd1151cab53ae8
--   exchange_ineligibility_reason(uuid)                       c6bebabc448b888a525ef895d5551859
--   exchange_invoice_details(uuid)                            9b8f97630794150edae2753469c0a99a
--   invoice_bill_to_source(uuid)                              f46d331ce5410681dfcb73ace9600ca3
--   invoice_legacy_entitlements(uuid)                         0cb40c6bf47d07e55dcda725d2e17c0c
--   invoice_revision_history(uuid)                            4b5143e1d62e17ae83c1cd7ff507aecf
--   invoice_therapy_summary(uuid)                             aa53b9ebea63c57f4b7c87253db8b21a
--   invoice_transferable_benefits(uuid)                       e3a4b753d87546a1a73342baf02bee70
--   legacy_qualification_diagnose(uuid,uuid,date)             e46813acdafbf7be537dffaa5fd3237b
--   legacy_reward_options(uuid)                               5d167cc1ac9d443f4b7d7d2566990770
--   legacy_reward_options_diagnostic(uuid)                    f99406c5ee8b9ce1587ed4190239da77
--   legacy_reward_voucher_options(uuid)                       8728d0ba59ddf0a9e7161ed3483c4618
--   legacy_setup_status()                                     613421e888aabd2920b27f4194c5ef9b
--   my_assigned_store_id()                                    e07a781a3d7c22742158245b62309993
--   pay_special_with_credit(text,uuid,uuid,numeric,uuid)      5496ea7f657d49629653defc905c88f2
--   premium_bundle_benefit_preview(uuid,uuid)                 ef66cef34d170f24b642eef3521f402c
--   premium_bundles_for_store(uuid,date)                      e8de14d2264ec3e551df0f52bb6a6524
--   products_available_as_special()                           0e39e3af72fe1f88bffdba9f50a61c2f
--   promotion_original_total(uuid,uuid)                       2480074e2b77e313b052cc225493087c
--   record_document_send(text,text,text,uuid,uuid,text,text,text,text)
--                                                             b602db515c9a685bf6fe642eb312b4ab
--   report_customer_sources(date,date)                        de5b160f34a49ff254c8f93cdc0f5106
--   resolve_tiktok_physical_return(uuid,boolean,text,text)    12ae6689e864b6374f3d5090f5fccb4b
--   return_stock_loan(uuid,jsonb,text,uuid)                   c79caeb845c31b3032f90df3d0e01778
--   special_docs_awaiting_fulfilment()                        aed7e3b24ff192cbe09935c5e7488881
--   special_product_availability(uuid)                        467b0d480d36f0535dd39bac1e5095a3
--   store_commission_staff(uuid)                              5debdc440bd1b3750e0a194c184f8f92
--   therapy_customer_detail(uuid)                             80abbc0a7b61f91c0a4248f9b18d8f4e
--   therapy_customer_summary(text,integer,integer,boolean)    55b69d8530418f74416bce23e3bdaa66
--   therapy_service_catalogue(uuid,boolean)                   3b1ffd4f7e1553b518ed65cb9eb6e43c
--   tiktok_negative_stock_alerts()                            e220e1441d930f34f58163ff5993db97
--   upsert_consultant_survey(uuid,text,text,text,text,boolean,boolean,boolean,boolean,text,uuid)
--                                                             d653a0edddef3023b7dac7b0f97e0964
--
-- DEPLOY ORDER: this, then 407 straight after, then the front end (pushing to
-- main deploys it), then reload the app on the shop's devices. The pages live
-- now keep working against this: they call every function above as active
-- staff. Two calls change: the Print buttons' write_audit is refused (the pages
-- ignore its answer, so printing works and only the "printed" audit row is
-- missing until the new pages call record_document_printed), and a login whose
-- role a page leaves out gets 42501 from customer_profile_stats and
-- dashboard_summary, which those pages already read as "no figures" (the new
-- pages no longer ask). The new pages against a database without this: the
-- Print buttons' record_document_printed does not exist yet, which they also
-- ignore.
--
-- Test: scripts/permissions/tests/staff-only-functions.sql (every function a
-- login can call, as logins that are not staff, and the pages' functions as
-- each role), scripts/permissions/tests/function-grants.sql.

set lock_timeout = '5s';

do $mig$
declare
  -- ── The two checks, and the Print buttons' audit row ──────────────────────
  c_staff_def constant text := $def$CREATE OR REPLACE FUNCTION public.require_active_staff(p_roles text[] DEFAULT NULL::text[])
 RETURNS user_role
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_role public.user_role;
begin
  -- 406: the first statement of a staff page's server function. Being signed
  -- in does not make a login staff: affiliates sign in, a login could be
  -- created by anyone, and a deactivated employee keeps their password. Only an
  -- active, accepted, not-deleted profile passes (as in user_admin_role), and
  -- with p_roles only a profile whose role is one of them. Refused: 42501.
  --
  -- The server is not a login. The service role (website orders, the Edge
  -- Functions), pg_cron and migrations carry neither the anon nor the
  -- authenticated role, and pass; a request from a browser always carries one.
  if coalesce(auth.role(), '') not in ('anon', 'authenticated') then
    return null;
  end if;
  select p.role into v_role from public.profiles p
   where p.id = auth.uid() and p.is_active and p.deleted_at is null
     and coalesce(p.invitation_status, 'accepted') = 'accepted';
  if v_role is null then
    raise exception 'Only active Energia staff can do this.' using errcode = '42501';
  end if;
  if p_roles is not null and not (v_role::text = any (p_roles)) then
    raise exception 'Your role cannot do this.' using errcode = '42501';
  end if;
  return v_role;
end
$function$
$def$;
  c_store_def constant text := $def$CREATE OR REPLACE FUNCTION public.require_store_access(p_store_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  -- 406: active staff who work at this store (user_has_store_access, so Owners
  -- and Admins reach every store). A null store leaves nothing to check beyond
  -- active staff. The server passes, as in require_active_staff.
  if coalesce(auth.role(), '') not in ('anon', 'authenticated') then
    return;
  end if;
  perform public.require_active_staff();
  if p_store_id is not null and not public.user_has_store_access(p_store_id) then
    raise exception 'That belongs to a store you are not assigned to.' using errcode = '42501';
  end if;
end
$function$
$def$;
  c_printed_def constant text := $def$CREATE OR REPLACE FUNCTION public.record_document_printed(p_kind text, p_record_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_store uuid; v_no text; v_ok boolean;
begin
  -- 406: the audit row the Print buttons leave, in place of calling
  -- write_audit, which wrote whatever table, record and action a browser sent.
  -- Two actions only, on a document the caller can see: an invoice of one of
  -- their stores (as the invoice list), an exchange as the Exchanges page.
  perform public.require_active_staff();
  if p_kind = 'invoice' then
    select i.store_id, i.invoice_no into v_store, v_no
      from public.invoices i where i.id = p_record_id and i.deleted_at is null;
    v_ok := v_no is not null and public.user_has_store_access(v_store);
  elsif p_kind = 'exchange' then
    select e.processing_store_id, e.exchange_no into v_store, v_no
      from public.product_exchanges e where e.id = p_record_id;
    v_ok := v_no is not null and (public.is_manager_or_above() or public.user_has_store_access(v_store));
  else
    raise exception 'Unknown document kind "%"', p_kind using errcode = '22023';
  end if;
  if not coalesce(v_ok, false) then
    raise exception 'That document is not one you can see.' using errcode = '42501';
  end if;
  perform public.write_audit(
    case p_kind when 'invoice' then 'invoices' else 'product_exchanges' end, p_record_id,
    case p_kind when 'invoice' then 'invoice_printed' else 'exchange_printed' end, null,
    case p_kind when 'invoice' then jsonb_build_object('invoice_no', v_no)
                else jsonb_build_object('exchange_no', v_no) end);
end
$function$
$def$;
  -- ── current_user_role(), whole ───────────────────────────────────────────
  c_role_def constant text := $def$CREATE OR REPLACE FUNCTION public.current_user_role()
 RETURNS user_role
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- 406: the role of an ACTIVE member of staff, else null. A deactivated
  -- employee, a pending or cancelled invitee and a deleted profile are nobody,
  -- as in user_admin_role(). Every policy and function that reads this takes
  -- null to mean "not staff".
  select p.role from public.profiles p
   where p.id = auth.uid() and p.is_active and p.deleted_at is null
     and coalesce(p.invitation_status, 'accepted') = 'accepted'
$function$
$def$;
  c_role_before constant text := 'b134c4be5f2c9db31c41dc029689d2c2';
  c_new constant text[][] := array[
    ['require_active_staff(text[])',       '877b3aa74cea559881979bb161c450e2'],
    ['require_store_access(uuid)',         'f9332fd2f0092337d64501d8a647c23f'],
    ['record_document_printed(text,uuid)', 'b67386018227a05327874c57e2acb9d2'],
    ['current_user_role()',                '519b0a33a3548f970c5d585b6e76a389']];
  -- "read profiles": staff, and since 406 also the login's own row
  c_read_profiles_before constant text := '(current_user_role() IS NOT NULL)';
  c_read_profiles_after  constant text := '((id = auth.uid()) OR (current_user_role() IS NOT NULL))';
  v_path text := current_setting('search_path');
  v_claims text := current_setting('request.jwt.claims', true);
  v_fns text[] := '{}'; v_defs text[] := '{}'; v_after text[] := '{}';
  v_acl text[]; v_new_state text[] := '{}';
  r record; v text; v_def text; i int; n int; v_bad text; v_owner uuid; v_role public.user_role;
begin
  perform set_config('search_path', 'public', true);

  -- ── Guards: nothing is installed unless all pass ─────────────────────────
  -- The new functions: missing, or already this version.
  for i in 1 .. array_length(c_new, 1) - 1 loop
    if to_regprocedure('public.' || c_new[i][1]) is null then
      v_new_state := v_new_state || 'missing'::text;
    elsif md5(pg_get_functiondef(to_regprocedure('public.' || c_new[i][1]))) = c_new[i][2] then
      v_new_state := v_new_state || 'done'::text;
    else
      raise exception '406: public.% exists and is not this migration''s version', c_new[i][1];
    end if;
  end loop;
  -- current_user_role(): the production version, or already this one.
  v := md5(pg_get_functiondef('public.current_user_role()'::regprocedure));
  if v not in (c_role_before, c_new[4][2]) then
    raise exception '406: public.current_user_role() is not the version read on 9 Oct 2026 (md5 %). Re-read it and re-test before applying.', v;
  end if;

  -- The patched functions: BEFORE (to patch) or AFTER (left alone).
  for r in select * from (values
    ('active_affiliates_for_picker()', '916a481a909edb09147d3caead51305a', '95316cbb02a3ecc6c078c8b877b14d6d'),
    ('active_foc_reasons()', '673f6f4b27299da95ecfdab5eba69612', '9d7d60ee289a56dfeccd6d2ed9c46732'),
    ('add_customer_remark(uuid,text,text,uuid)', '2e9a0327fb1c66e9a56d1862a7aaf568', 'cb073e29fb2de5ec92628a7220188be4'),
    ('affiliate_legacy_day_summary(date)', 'a5deac1fba5880636f0cda357dadab42', 'f0170fcb61ff1a40c07d532186669212'),
    ('bundle_line_components(uuid)', '799461c5855df161cf48ea3eabf5a4cc', '93ebc0e25991428c5e94a71879bbef41'),
    ('cancel_transfer_request(uuid)', '5f4d42e33c83bfab0b922474babecbb5', 'b12baadcf077487a6c275877275c4750'),
    ('claim_entitlement_vouchers(uuid,jsonb,text)', 'a0215fa3aaaa162772fa6e4dd9ea08bd', 'e6958c6052d3dd8d7ea3a175d614b5da'),
    ('claim_legacy_therapy(uuid,date,uuid,jsonb,text,text)', 'f14136078f691d743b6a0def4a874b09', '3957f56f3ea9dc8df6789371a20add66'),
    ('consultant_notes_for(uuid,uuid)', '9902c96cf8295d11ab4e237dedc60f19', '4f894f72b4af092d7ddd1421b3ab8597'),
    ('credit_package_benefit_preview(uuid,uuid)', 'e0e5dd9571e42c1c2248bc0bc4fea8a9', '4a79692ddfb66374f352c9a6bf9fe565'),
    ('credit_package_effective_rules(uuid)', '8daf32528ae969300ed4bdc9ba13f955', '0b8e865eb1c56e15db885753ffe6f1ee'),
    ('credit_packages_for_store(uuid,date)', '31a4a17f994467786e0cd3202324b578', '85df02046be2b8afc1fa9b685b37aca0'),
    ('customer_overview(uuid)', 'c2dfc1bd43e61699338598bda27e6303', '74e9cddfb699ed78369ee4d01578116e'),
    ('customer_profile_stats(uuid)', 'bca7226679aed8fd44ed9b646a7af27a', '67c5770c7bc0be83899e5fde593fc851'),
    ('customer_purchase_timeline(uuid)', 'fdf6a2c95663ccbac05d7276defdb5dc', 'cb21b1612cc04f5da2e5f07c46f81d0d'),
    ('customer_survey_overview(text,text,integer,integer)', 'b341a5207c6cd72082cc571f1a44b6cc', 'e84eb56b42505e2f8a34e6e7486cf6f9'),
    ('dashboard_alerts_summary()', '13122db6bf0b5c22ea2482e8d28a42af', 'c3a45ca21c315d5cd6bd1bf36108d905'),
    ('dashboard_credit_by_store(text,date,date)', '98157ff3234002bbf0faad93ee746e99', 'fe25ab311d6e3655500dea66c07fa0f1'),
    ('dashboard_credit_spend(text,date,date,uuid)', '4515b567863253ad3cf3e450852aaacf', '540ee810178c15f5c09a6b305bc4bd0d'),
    ('dashboard_summary()', '144fa049474bf7d2932cf5f9bac094be', '96ddc8f96a9bb00a222f11860d2ac221'),
    ('entitlement_voucher_state(uuid)', '80264a4e7fa785b8dca628a41d0145b1', 'f8b6a3a4521e025ed2cd1151cab53ae8'),
    ('exchange_ineligibility_reason(uuid)', '605f70041cd659acbaed2c0347bdbc92', 'c6bebabc448b888a525ef895d5551859'),
    ('exchange_invoice_details(uuid)', '358c33245d0c0bd52e9b96f009b9687b', '9b8f97630794150edae2753469c0a99a'),
    ('invoice_bill_to_source(uuid)', 'd6fae8edb4b1930589c793ed61de8830', 'f46d331ce5410681dfcb73ace9600ca3'),
    ('invoice_legacy_entitlements(uuid)', 'f2db5293a473c1a26582519c80ec6dde', '0cb40c6bf47d07e55dcda725d2e17c0c'),
    ('invoice_revision_history(uuid)', '6111514b5b8396d1304d43f14ae8cf69', '4b5143e1d62e17ae83c1cd7ff507aecf'),
    ('invoice_therapy_summary(uuid)', '52ce8a657627bc919d1580fc6b316e18', 'aa53b9ebea63c57f4b7c87253db8b21a'),
    ('invoice_transferable_benefits(uuid)', '53b7e5631c96fb56273c08354bf8442b', 'e3a4b753d87546a1a73342baf02bee70'),
    ('legacy_qualification_diagnose(uuid,uuid,date)', '70221c452ec55d19f31ae443a984b1a3', 'e46813acdafbf7be537dffaa5fd3237b'),
    ('legacy_reward_options(uuid)', '92a9255cc922d668f885888b208b4560', '5d167cc1ac9d443f4b7d7d2566990770'),
    ('legacy_reward_options_diagnostic(uuid)', '743db28f35ff92291373f58703366cbb', 'f99406c5ee8b9ce1587ed4190239da77'),
    ('legacy_reward_voucher_options(uuid)', 'd4f3df259b63ee561837a3d7890c5f5f', '8728d0ba59ddf0a9e7161ed3483c4618'),
    ('legacy_setup_status()', 'e2f1a408b8f630fd29d870e1f7fd5326', '613421e888aabd2920b27f4194c5ef9b'),
    ('my_assigned_store_id()', 'b4864f1257e48312c4a273f241f8c1c5', 'e07a781a3d7c22742158245b62309993'),
    ('pay_special_with_credit(text,uuid,uuid,numeric,uuid)', 'dfbae74ac655ea4e711db90ea9adacfc', '5496ea7f657d49629653defc905c88f2'),
    ('premium_bundle_benefit_preview(uuid,uuid)', '3e0de91e323105ef941c434d0bdeacdc', 'ef66cef34d170f24b642eef3521f402c'),
    ('premium_bundles_for_store(uuid,date)', '0b8b5b2a16747e6a12c217098a78ff7e', 'e8de14d2264ec3e551df0f52bb6a6524'),
    ('products_available_as_special()', '8e76dcac282b039735ced84fd2707c93', '0e39e3af72fe1f88bffdba9f50a61c2f'),
    ('promotion_original_total(uuid,uuid)', '9712b8d78d474896aac89081469afd30', '2480074e2b77e313b052cc225493087c'),
    ('record_document_send(text,text,text,uuid,uuid,text,text,text,text)', 'd4b4aff765a161e58f31fda2d2e37ef8', 'b602db515c9a685bf6fe642eb312b4ab'),
    ('report_customer_sources(date,date)', '1b54e0dd1ea7b215c396ca87c760555e', 'de5b160f34a49ff254c8f93cdc0f5106'),
    ('resolve_tiktok_physical_return(uuid,boolean,text,text)', '844cf27fde0936e93f20b3a05ad8dfe7', '12ae6689e864b6374f3d5090f5fccb4b'),
    ('return_stock_loan(uuid,jsonb,text,uuid)', '978c886b03ccae32d48de8bc78667975', 'c79caeb845c31b3032f90df3d0e01778'),
    ('special_docs_awaiting_fulfilment()', 'ff0f89048581abdfac941fdf84e39514', 'aed7e3b24ff192cbe09935c5e7488881'),
    ('special_product_availability(uuid)', '57d4d5e52f787dc71d957c4ba9276045', '467b0d480d36f0535dd39bac1e5095a3'),
    ('store_commission_staff(uuid)', '7aca1c0300eb821fa8b825761c211f98', '5debdc440bd1b3750e0a194c184f8f92'),
    ('therapy_customer_detail(uuid)', 'fcbedaa5ef6f2f56c3271d3c6d6690ec', '80abbc0a7b61f91c0a4248f9b18d8f4e'),
    ('therapy_customer_summary(text,integer,integer,boolean)', '6bb0f3b4b81882f51ee4f4e115391779', '55b69d8530418f74416bce23e3bdaa66'),
    ('therapy_service_catalogue(uuid,boolean)', 'd4bcd45afab45f2a63a18650c2b5412d', '3b1ffd4f7e1553b518ed65cb9eb6e43c'),
    ('tiktok_negative_stock_alerts()', '7415c756855445f041c5a616de345573', 'e220e1441d930f34f58163ff5993db97'),
    ('upsert_consultant_survey(uuid,text,text,text,text,boolean,boolean,boolean,boolean,text,uuid)', '1389c4734bffe9b21dfbfad35a17c38a', 'd653a0edddef3023b7dac7b0f97e0964')
  ) x(fn, before_md5, after_md5)
  loop
    if to_regprocedure('public.' || r.fn) is null then
      raise exception '406: public.% is missing', r.fn; end if;
    v_def := pg_get_functiondef(to_regprocedure('public.' || r.fn));
    if md5(v_def) = r.after_md5 then continue; end if;
    if md5(v_def) <> r.before_md5 then
      raise exception '406: public.% is not the version read from production on 9 Oct 2026 (md5 %). Re-read it and re-test before applying.', r.fn, md5(v_def); end if;
    v_fns := v_fns || r.fn; v_defs := v_defs || v_def; v_after := v_after || r.after_md5;
  end loop;

  -- The revoked functions and the helpers relied on: the versions read on 9 Oct.
  for r in select * from (values
    ('write_audit(text,uuid,text,jsonb,jsonb)', '19cd6b07bdbb6c73c26fb8aa83d2463e'),
    ('auth_email_user_state(text)', '2e95d18a8d08dac7d54f4e98c94b7998'),
    ('auth_email_reserve(text,text,text)', 'e391dd051d05f0661c7924f24e04a1b2'),
    ('auth_email_record_outcome(uuid,text,text,text,integer,text)', 'c0d13ae48f06851f2845d13adad03e60'),
    ('commission_outside_rebase_scope()', 'd91d28959dd66cfd91b1fd8522e9c724'),
    ('commission_totals_reconciliation()', '5830555097c3e489dd9f2e799af9d87a'),
    ('preview_commission_rebase_effect(date,date)', '4aa9ebaf897a1c3aa97cac944a8180e4'),
    ('validate_bundle_voucher_selection(uuid,uuid,jsonb)', '16e707758a4d771c49c403ef8983570f'),
    ('user_has_store_access(uuid)', '8c82c6bcb64f496c5a05a2b8dafa95f8'),
    ('is_manager_or_above()', 'f12b9ed342070fa4defa30e4da2ba655'),
    ('sg_today()', '1c1289f18e24d8370e9a6364c9c06fca'),
    ('write_audit_ex(text,uuid,text,jsonb,jsonb,text,text,uuid,text,text)', 'c705c733e213a27f0dc32d54322cc855'),
    ('user_admin_role()', '6fe6c3202163ce80babdcf04fc28f76b'),
    ('health_survey_detail(uuid)', 'e04b50ad8507d77e9436e2a2a84766d1')
  ) x(fn, md5)
  loop
    if to_regprocedure('public.' || r.fn) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || r.fn))) <> r.md5 then
      raise exception '406: public.% is missing or not the version read on 9 Oct 2026. Re-read it and re-test before applying.', r.fn; end if;
  end loop;

  -- No other function takes these names (the API picks an overload by name).
  select string_agg(p.oid::regprocedure::text, ', ') into v_bad
    from pg_proc p
   where p.pronamespace = 'public'::regnamespace
     and p.proname = any (array['active_affiliates_for_picker', 'active_foc_reasons', 'add_customer_remark', 'affiliate_legacy_day_summary', 'auth_email_record_outcome', 'auth_email_reserve', 'auth_email_user_state', 'bundle_line_components', 'cancel_transfer_request', 'claim_entitlement_vouchers', 'claim_legacy_therapy', 'commission_outside_rebase_scope', 'commission_totals_reconciliation', 'consultant_notes_for', 'credit_package_benefit_preview', 'credit_package_effective_rules', 'credit_packages_for_store', 'current_user_role', 'customer_overview', 'customer_profile_stats', 'customer_purchase_timeline', 'customer_survey_overview', 'dashboard_alerts_summary', 'dashboard_credit_by_store', 'dashboard_credit_spend', 'dashboard_summary', 'entitlement_voucher_state', 'exchange_ineligibility_reason', 'exchange_invoice_details', 'invoice_bill_to_source', 'invoice_legacy_entitlements', 'invoice_revision_history', 'invoice_therapy_summary', 'invoice_transferable_benefits', 'legacy_qualification_diagnose', 'legacy_reward_options', 'legacy_reward_options_diagnostic', 'legacy_reward_voucher_options', 'legacy_setup_status', 'my_assigned_store_id', 'pay_special_with_credit', 'premium_bundle_benefit_preview', 'premium_bundles_for_store', 'preview_commission_rebase_effect', 'products_available_as_special', 'promotion_original_total', 'record_document_printed', 'record_document_send', 'report_customer_sources', 'require_active_staff', 'require_store_access', 'resolve_tiktok_physical_return', 'return_stock_loan', 'special_docs_awaiting_fulfilment', 'special_product_availability', 'store_commission_staff', 'therapy_customer_detail', 'therapy_customer_summary', 'therapy_service_catalogue', 'tiktok_negative_stock_alerts', 'upsert_consultant_survey', 'validate_bundle_voucher_selection', 'write_audit'])
     and p.oid::regprocedure::text <> all (array['active_affiliates_for_picker()', 'active_foc_reasons()', 'add_customer_remark(uuid,text,text,uuid)', 'affiliate_legacy_day_summary(date)', 'auth_email_record_outcome(uuid,text,text,text,integer,text)', 'auth_email_reserve(text,text,text)', 'auth_email_user_state(text)', 'bundle_line_components(uuid)', 'cancel_transfer_request(uuid)', 'claim_entitlement_vouchers(uuid,jsonb,text)', 'claim_legacy_therapy(uuid,date,uuid,jsonb,text,text)', 'commission_outside_rebase_scope()', 'commission_totals_reconciliation()', 'consultant_notes_for(uuid,uuid)', 'credit_package_benefit_preview(uuid,uuid)', 'credit_package_effective_rules(uuid)', 'credit_packages_for_store(uuid,date)', 'current_user_role()', 'customer_overview(uuid)', 'customer_profile_stats(uuid)', 'customer_purchase_timeline(uuid)', 'customer_survey_overview(text,text,integer,integer)', 'dashboard_alerts_summary()', 'dashboard_credit_by_store(text,date,date)', 'dashboard_credit_spend(text,date,date,uuid)', 'dashboard_summary()', 'entitlement_voucher_state(uuid)', 'exchange_ineligibility_reason(uuid)', 'exchange_invoice_details(uuid)', 'invoice_bill_to_source(uuid)', 'invoice_legacy_entitlements(uuid)', 'invoice_revision_history(uuid)', 'invoice_therapy_summary(uuid)', 'invoice_transferable_benefits(uuid)', 'legacy_qualification_diagnose(uuid,uuid,date)', 'legacy_reward_options(uuid)', 'legacy_reward_options_diagnostic(uuid)', 'legacy_reward_voucher_options(uuid)', 'legacy_setup_status()', 'my_assigned_store_id()', 'pay_special_with_credit(text,uuid,uuid,numeric,uuid)', 'premium_bundle_benefit_preview(uuid,uuid)', 'premium_bundles_for_store(uuid,date)', 'preview_commission_rebase_effect(date,date)', 'products_available_as_special()', 'promotion_original_total(uuid,uuid)', 'record_document_printed(text,uuid)', 'record_document_send(text,text,text,uuid,uuid,text,text,text,text)', 'report_customer_sources(date,date)', 'require_active_staff(text[])', 'require_store_access(uuid)', 'resolve_tiktok_physical_return(uuid,boolean,text,text)', 'return_stock_loan(uuid,jsonb,text,uuid)', 'special_docs_awaiting_fulfilment()', 'special_product_availability(uuid)', 'store_commission_staff(uuid)', 'therapy_customer_detail(uuid)', 'therapy_customer_summary(text,integer,integer,boolean)', 'therapy_service_catalogue(uuid,boolean)', 'tiktok_negative_stock_alerts()', 'upsert_consultant_survey(uuid,text,text,text,text,boolean,boolean,boolean,boolean,text,uuid)', 'validate_bundle_voucher_selection(uuid,uuid,jsonb)', 'write_audit(text,uuid,text,jsonb,jsonb)']);
  if v_bad is not null then
    raise exception '406: another function takes one of these names: %', v_bad; end if;

  -- "read profiles": as read on 9 Oct, or already this migration's.
  select p.qual into v from pg_policies p
   where p.schemaname = 'public' and p.tablename = 'profiles' and p.policyname = 'read profiles'
     and p.cmd = 'SELECT' and p.roles = '{authenticated}' and p.with_check is null;
  if v is null or v not in (c_read_profiles_before, c_read_profiles_after) then
    raise exception '406: the policy "read profiles" is not the one read on 9 Oct 2026 (%)', v; end if;

  -- ── Build every new text before installing anything ─────────────────────
  for r in select * from (values
    (1, 'active_affiliates_for_picker()', $a$AS $function$
$a$,
         $r$AS $function$
  select public.require_active_staff();  -- 406: active staff only
$r$),
    (2, 'active_foc_reasons()', $a$AS $function$
$a$,
         $r$AS $function$
  select public.require_active_staff();  -- 406: active staff only
$r$),
    (3, 'add_customer_remark(uuid,text,text,uuid)', $a$begin
  if p_customer_id is null then raise exception 'A customer is required'; end if;
$a$,
         $r$begin
  perform public.require_active_staff('{owner,manager}');  -- 406: active Owners and Managers only
  if p_customer_id is null then raise exception 'A customer is required'; end if;
$r$),
    (4, 'add_customer_remark(uuid,text,text,uuid)', $a$  insert into public.customer_remarks (customer_id, survey_id, remark, remark_type, created_by)
$a$,
         $r$  -- 406: a live customer, and a survey that is theirs.
  if not exists (select 1 from public.customers c where c.id = p_customer_id and c.deleted_at is null) then
    raise exception 'Customer not found'; end if;
  if p_survey_id is not null and not exists (select 1 from public.health_surveys s
                                              where s.id = p_survey_id and s.customer_id = p_customer_id) then
    raise exception 'That survey is not this customer''s'; end if;
  insert into public.customer_remarks (customer_id, survey_id, remark, remark_type, created_by)
$r$),
    (5, 'affiliate_legacy_day_summary(date)', $a$begin
  for v_a in
$a$,
         $r$begin
  perform public.require_active_staff('{owner,manager}');  -- 406: active Owners and Managers only
  for v_a in
$r$),
    (6, 'bundle_line_components(uuid)', $a$AS $function$
$a$,
         $r$AS $function$
  select public.require_active_staff();  -- 406: active staff only
$r$),
    (7, 'cancel_transfer_request(uuid)', $a$begin
  select * into v_req from public.transfer_requests where id = p_request_id for update;
$a$,
         $r$begin
  perform public.require_active_staff();  -- 406: active staff only
  select * into v_req from public.transfer_requests where id = p_request_id for update;
$r$),
    (8, 'claim_entitlement_vouchers(uuid,jsonb,text)', $a$begin
  -- for update: two tabs, or a retried request, must not both claim the last one.
$a$,
         $r$begin
  perform public.require_active_staff();  -- 406: active staff only
  -- for update: two tabs, or a retried request, must not both claim the last one.
$r$),
    (9, 'claim_legacy_therapy(uuid,date,uuid,jsonb,text,text)', $a$begin
  -- for update: two clicks, two tabs, or a retried request must not both claim.
$a$,
         $r$begin
  perform public.require_active_staff();  -- 406: active staff only
  -- for update: two clicks, two tabs, or a retried request must not both claim.
$r$),
    (10, 'consultant_notes_for(uuid,uuid)', $a$AS $function$
$a$,
         $r$AS $function$
  select public.require_active_staff('{owner,admin,manager,staff}');  -- 406: active staff only, not Inventory Managers
$r$),
    (11, 'consultant_notes_for(uuid,uuid)', $a$  where (p_survey_id is null or n.survey_id = p_survey_id)
$a$,
         $r$  where (p_survey_id is not null or p_customer_id is not null)  -- 406: one survey or one customer, never all
    and (p_survey_id is null or n.survey_id = p_survey_id)
$r$),
    (12, 'credit_package_benefit_preview(uuid,uuid)', $a$begin
  select * into pk from public.credit_packages where id = p_package_id and deleted_at is null;
$a$,
         $r$begin
  perform public.require_active_staff();  -- 406: active staff only
  select * into pk from public.credit_packages where id = p_package_id and deleted_at is null;
$r$),
    (13, 'credit_package_effective_rules(uuid)', $a$AS $function$
$a$,
         $r$AS $function$
  select public.require_active_staff();  -- 406: active staff only
$r$),
    (14, 'credit_packages_for_store(uuid,date)', $a$AS $function$
$a$,
         $r$AS $function$
  select public.require_active_staff();  -- 406: active staff only
$r$),
    (15, 'customer_overview(uuid)', $a$begin
  v_out := jsonb_build_object(
$a$,
         $r$begin
  perform public.require_active_staff();  -- 406: active staff only
  v_out := jsonb_build_object(
$r$),
    (16, 'customer_profile_stats(uuid)', $a$begin
  select count(*), coalesce(sum(total_amount),0)
$a$,
         $r$begin
  perform public.require_active_staff('{owner,manager}');  -- 406: active Owners and Managers only
  select count(*), coalesce(sum(total_amount),0)
$r$),
    (17, 'customer_purchase_timeline(uuid)', $a$AS $function$
$a$,
         $r$AS $function$
  select public.require_active_staff('{owner,manager}');  -- 406: active Owners and Managers only
$r$),
    (18, 'customer_survey_overview(text,text,integer,integer)', $a$AS $function$
$a$,
         $r$AS $function$
  select public.require_active_staff();  -- 406: active staff only
$r$),
    (19, 'customer_survey_overview(text,text,integer,integer)', $a$   limit greatest(coalesce(p_limit,50),1)
$a$,
         $r$   limit least(greatest(coalesce(p_limit,50),1), 200)  -- 406: at most 200 a page
$r$),
    (20, 'dashboard_alerts_summary()', $a$AS $function$
$a$,
         $r$AS $function$
  select public.require_active_staff();  -- 406: active staff only
$r$),
    (21, 'dashboard_credit_by_store(text,date,date)', $a$begin
  select role into v_role from public.profiles where id = auth.uid();
$a$,
         $r$begin
  perform public.require_active_staff();  -- 406: active staff only
  select role into v_role from public.profiles where id = auth.uid();
$r$),
    (22, 'dashboard_credit_spend(text,date,date,uuid)', $a$begin
  select role into v_role from public.profiles where id = auth.uid();
$a$,
         $r$begin
  perform public.require_active_staff();  -- 406: active staff only
  select role into v_role from public.profiles where id = auth.uid();
$r$),
    (23, 'dashboard_summary()', $a$begin
  v_out := jsonb_build_object(
$a$,
         $r$begin
  perform public.require_active_staff('{owner,admin,manager}');  -- 406: active Owners, Admins and Managers only
  v_out := jsonb_build_object(
$r$),
    (24, 'entitlement_voucher_state(uuid)', $a$begin
  select * into e from public.therapy_entitlements where id = p_entitlement_id;
$a$,
         $r$begin
  perform public.require_active_staff();  -- 406: active staff only
  select * into e from public.therapy_entitlements where id = p_entitlement_id;
$r$),
    (25, 'exchange_ineligibility_reason(uuid)', $a$begin
  select * into v_inv from public.invoices where id = p_invoice_id;
$a$,
         $r$begin
  perform public.require_active_staff();  -- 406: active staff only
  select * into v_inv from public.invoices where id = p_invoice_id;
$r$),
    (26, 'exchange_invoice_details(uuid)', $a$begin
  select * into v_inv from public.invoices where id = p_invoice_id;
$a$,
         $r$begin
  perform public.require_store_access((select i.store_id from public.invoices i where i.id = p_invoice_id));  -- 406: active staff of the invoice's store only
  select * into v_inv from public.invoices where id = p_invoice_id;
$r$),
    (27, 'invoice_bill_to_source(uuid)', $a$AS $function$
$a$,
         $r$AS $function$
  select public.require_store_access((select i.store_id from public.invoices i where i.id = p_invoice_id));  -- 406: active staff of the invoice's store only
$r$),
    (28, 'invoice_legacy_entitlements(uuid)', $a$begin
  select * into v_inv from public.invoices where id = p_invoice_id;
$a$,
         $r$begin
  perform public.require_store_access((select i.store_id from public.invoices i where i.id = p_invoice_id));  -- 406: active staff of the invoice's store only
  select * into v_inv from public.invoices where id = p_invoice_id;
$r$),
    (29, 'invoice_revision_history(uuid)', $a$AS $function$
$a$,
         $r$AS $function$
  select public.require_store_access((select i.store_id from public.invoices i where i.id = p_invoice_id));  -- 406: active staff of the invoice's store only
$r$),
    (30, 'invoice_therapy_summary(uuid)', $a$begin
  select * into v_inv from public.invoices where id = p_invoice_id;
$a$,
         $r$begin
  perform public.require_store_access((select i.store_id from public.invoices i where i.id = p_invoice_id));  -- 406: active staff of the invoice's store only
  select * into v_inv from public.invoices where id = p_invoice_id;
$r$),
    (31, 'invoice_transferable_benefits(uuid)', $a$AS $function$
$a$,
         $r$AS $function$
  select public.require_store_access((select i.store_id from public.invoices i where i.id = p_invoice_id));  -- 406: active staff of the invoice's store only
$r$),
    (32, 'legacy_qualification_diagnose(uuid,uuid,date)', $a$begin
  if p_customer_id is null then
$a$,
         $r$begin
  perform public.require_store_access(p_store_id);  -- 406: active staff of that store only
  if p_customer_id is null then
$r$),
    (33, 'legacy_reward_options(uuid)', $a$begin
  select * into e from public.therapy_entitlements where id = p_entitlement_id;
$a$,
         $r$begin
  perform public.require_active_staff();  -- 406: active staff only
  select * into e from public.therapy_entitlements where id = p_entitlement_id;
$r$),
    (34, 'legacy_reward_options_diagnostic(uuid)', $a$begin
  select * into e from public.therapy_entitlements where id = p_entitlement_id;
$a$,
         $r$begin
  perform public.require_active_staff();  -- 406: active staff only
  select * into e from public.therapy_entitlements where id = p_entitlement_id;
$r$),
    (35, 'legacy_reward_voucher_options(uuid)', $a$AS $function$
$a$,
         $r$AS $function$
  select public.require_active_staff();  -- 406: active staff only
$r$),
    (36, 'legacy_setup_status()', $a$begin
  select count(*) into v_cust from public.therapy_package_rules
$a$,
         $r$begin
  perform public.require_active_staff();  -- 406: active staff only
  select count(*) into v_cust from public.therapy_package_rules
$r$),
    (37, 'my_assigned_store_id()', $a$  where usa.user_id = auth.uid() and p.role = 'staff'
$a$,
         $r$  where usa.user_id = auth.uid() and p.role = 'staff'
    and p.is_active and p.deleted_at is null
    and coalesce(p.invitation_status, 'accepted') = 'accepted'  -- 406: an active member of staff only
$r$),
    (38, 'pay_special_with_credit(text,uuid,uuid,numeric,uuid)', $a$begin
  if p_customer_id is null then raise exception 'Wallet credit needs a customer'; end if;
$a$,
         $r$begin
  perform public.require_active_staff('{owner,manager}');  -- 406: active Owners and Managers only
  if p_customer_id is null then raise exception 'Wallet credit needs a customer'; end if;
$r$),
    (39, 'premium_bundle_benefit_preview(uuid,uuid)', $a$begin
  select * into b from public.premium_bundles where id = p_bundle_id and deleted_at is null;
$a$,
         $r$begin
  perform public.require_active_staff();  -- 406: active staff only
  select * into b from public.premium_bundles where id = p_bundle_id and deleted_at is null;
$r$),
    (40, 'premium_bundles_for_store(uuid,date)', $a$AS $function$
$a$,
         $r$AS $function$
  select public.require_active_staff();  -- 406: active staff only
$r$),
    (41, 'products_available_as_special()', $a$AS $function$
$a$,
         $r$AS $function$
  select public.require_active_staff('{owner,manager}');  -- 406: active Owners and Managers only
$r$),
    (42, 'promotion_original_total(uuid,uuid)', $a$begin
  for v_item in select * from public.promotion_items where promotion_id = p_promotion_id
$a$,
         $r$begin
  perform public.require_active_staff();  -- 406: active staff only
  for v_item in select * from public.promotion_items where promotion_id = p_promotion_id
$r$),
    (43, 'record_document_send(text,text,text,uuid,uuid,text,text,text,text)', $a$begin
  insert into public.document_sends (doc_kind, doc_id, doc_no, customer_id, channel,
$a$,
         $r$begin
  perform public.require_active_staff();  -- 406: active staff only
  insert into public.document_sends (doc_kind, doc_id, doc_no, customer_id, channel,
$r$),
    (44, 'report_customer_sources(date,date)', $a$AS $function$
$a$,
         $r$AS $function$
  select public.require_active_staff();  -- 406: active staff only
$r$),
    (45, 'resolve_tiktok_physical_return(uuid,boolean,text,text)', $a$begin
  v_role := public.current_user_role();
$a$,
         $r$begin
  perform public.require_active_staff();  -- 406: active staff only
  v_role := public.current_user_role();
$r$),
    (46, 'return_stock_loan(uuid,jsonb,text,uuid)', $a$begin
  if p_loan_id is null then raise exception 'Loan not found'; end if;
$a$,
         $r$begin
  perform public.require_active_staff();  -- 406: active staff only
  if p_loan_id is null then raise exception 'Loan not found'; end if;
$r$),
    (47, 'special_docs_awaiting_fulfilment()', $a$AS $function$
$a$,
         $r$AS $function$
  select public.require_active_staff('{owner,manager}');  -- 406: active Owners and Managers only
$r$),
    (48, 'special_product_availability(uuid)', $a$AS $function$
$a$,
         $r$AS $function$
  select public.require_active_staff('{owner,manager}');  -- 406: active Owners and Managers only
$r$),
    (49, 'store_commission_staff(uuid)', $a$AS $function$
$a$,
         $r$AS $function$
  select public.require_active_staff();  -- 406: active staff only
$r$),
    (50, 'therapy_customer_detail(uuid)', $a$begin
  select jsonb_build_object(
$a$,
         $r$begin
  perform public.require_active_staff();  -- 406: active staff only
  select jsonb_build_object(
$r$),
    (51, 'therapy_customer_summary(text,integer,integer,boolean)', $a$AS $function$
$a$,
         $r$AS $function$
  select public.require_active_staff();  -- 406: active staff only
$r$),
    (52, 'therapy_service_catalogue(uuid,boolean)', $a$AS $function$
$a$,
         $r$AS $function$
  select public.require_active_staff('{owner,admin,manager}');  -- 406: active Owners, Admins and Managers only
$r$),
    (53, 'tiktok_negative_stock_alerts()', $a$AS $function$
$a$,
         $r$AS $function$
  select public.require_active_staff();  -- 406: active staff only
$r$),
    (54, 'upsert_consultant_survey(uuid,text,text,text,text,boolean,boolean,boolean,boolean,text,uuid)', $a$declare c public.customers%rowtype; v_id uuid; v_no text; v_store uuid;
begin
$a$,
         $r$declare c public.customers%rowtype; v_id uuid; v_no text; v_store uuid; v_role public.user_role;
begin
  -- 406: active staff only, not Inventory Managers (health declarations are not
  -- their remit, as in health_survey_detail). The consultant's findings are an
  -- Owner's or a Manager's, as in review_health_survey; the Surveys page sends
  -- none of them.
  v_role := public.require_active_staff('{owner,admin,manager,staff}');
  if v_role is not null and v_role not in ('owner', 'manager')
     and coalesce(p_remarks_condition, p_remarks_recommendation, p_acidity_result, p_health_goals) is not null then
    raise exception 'Only an Owner or Manager can write the consultant''s findings'
      using errcode = '42501';
  end if;
$r$),
    (55, 'upsert_consultant_survey(uuid,text,text,text,text,boolean,boolean,boolean,boolean,text,uuid)', $a$  select * into c from public.customers where id = p_customer_id;
  if not found then raise exception 'Customer not found'; end if;
$a$,
         $r$  -- 406: the row lock makes a second quick click wait and then find the first
  -- click's survey, instead of failing on the one-survey-per-customer rule.
  select * into c from public.customers where id = p_customer_id for update;
  if not found or c.deleted_at is not null then raise exception 'Customer not found'; end if;
$r$),
    (56, 'upsert_consultant_survey(uuid,text,text,text,text,boolean,boolean,boolean,boolean,text,uuid)', $a$    v_no := 'HS-' || to_char(now(), 'YYYYMMDD') || '-' || substr(md5(random()::text), 1, 6);
$a$,
         $r$    v_no := 'HS-' || to_char(public.sg_today(), 'YYYYMMDD') || '-' || substr(md5(random()::text), 1, 6);  -- 406: the Singapore date
$r$)
  ) x(ord, fn, anchor, repl) order by ord
  loop
    i := array_position(v_fns, r.fn);
    if i is null then continue; end if;               -- already this migration's
    n := (length(v_defs[i]) - length(replace(v_defs[i], r.anchor, ''))) / length(r.anchor);
    if n <> 1 then
      raise exception '406: an anchor occurs % times in public.%: %', n, r.fn, left(r.anchor, 80); end if;
    v_defs[i] := replace(v_defs[i], r.anchor, r.repl);
  end loop;
  for i in 1 .. coalesce(array_length(v_fns, 1), 0) loop
    if md5(v_defs[i]) <> v_after[i] then
      raise exception '406: the text built for public.% is not the one tested (md5 %)', v_fns[i], md5(v_defs[i]); end if;
  end loop;

  select array_agg(coalesce(p.proacl::text, '') order by p.oid::regprocedure::text) into v_acl
    from pg_proc p where p.pronamespace = 'public'::regnamespace
     and p.oid::regprocedure::text = any (array_append(v_fns, 'current_user_role()'));

  -- ── Install: the checks first, then what calls them ─────────────────────
  if v_new_state[1] = 'missing' then
    execute c_staff_def;
    revoke all on function public.require_active_staff(text[]) from public, anon, authenticated;
    grant execute on function public.require_active_staff(text[]) to service_role;
  end if;
  if v_new_state[2] = 'missing' then
    execute c_store_def;
    revoke all on function public.require_store_access(uuid) from public, anon, authenticated;
    grant execute on function public.require_store_access(uuid) to service_role;
  end if;
  if md5(pg_get_functiondef('public.current_user_role()'::regprocedure)) = c_role_before then
    execute c_role_def;
  end if;
  for i in 1 .. coalesce(array_length(v_fns, 1), 0) loop
    execute v_defs[i];
  end loop;
  if v_new_state[3] = 'missing' then
    execute c_printed_def;
    revoke all on function public.record_document_printed(text,uuid) from public, anon;
    grant execute on function public.record_document_printed(text,uuid) to authenticated, service_role;
  end if;
  for r in select * from (values
    ('write_audit(text,uuid,text,jsonb,jsonb)', '19cd6b07bdbb6c73c26fb8aa83d2463e'),
    ('auth_email_user_state(text)', '2e95d18a8d08dac7d54f4e98c94b7998'),
    ('auth_email_reserve(text,text,text)', 'e391dd051d05f0661c7924f24e04a1b2'),
    ('auth_email_record_outcome(uuid,text,text,text,integer,text)', 'c0d13ae48f06851f2845d13adad03e60'),
    ('commission_outside_rebase_scope()', 'd91d28959dd66cfd91b1fd8522e9c724'),
    ('commission_totals_reconciliation()', '5830555097c3e489dd9f2e799af9d87a'),
    ('preview_commission_rebase_effect(date,date)', '4aa9ebaf897a1c3aa97cac944a8180e4'),
    ('validate_bundle_voucher_selection(uuid,uuid,jsonb)', '16e707758a4d771c49c403ef8983570f')
  ) x(fn, md5)
  loop
    execute format('revoke all on function public.%s from public, anon, authenticated', r.fn);
    execute format('grant execute on function public.%s to service_role', r.fn);
  end loop;
  alter policy "read profiles" on public.profiles
    using ((id = auth.uid()) or (public.current_user_role() is not null));

  -- ── Installed exactly as tested ──────────────────────────────────────────
  for i in 1 .. array_length(c_new, 1) loop
    v := md5(pg_get_functiondef(to_regprocedure('public.' || c_new[i][1])));
    if v <> c_new[i][2] then v_bad := concat_ws('; ', v_bad, c_new[i][1] || ' ' || v); end if;
  end loop;
  for r in select * from (values
    ('active_affiliates_for_picker()', '916a481a909edb09147d3caead51305a', '95316cbb02a3ecc6c078c8b877b14d6d'),
    ('active_foc_reasons()', '673f6f4b27299da95ecfdab5eba69612', '9d7d60ee289a56dfeccd6d2ed9c46732'),
    ('add_customer_remark(uuid,text,text,uuid)', '2e9a0327fb1c66e9a56d1862a7aaf568', 'cb073e29fb2de5ec92628a7220188be4'),
    ('affiliate_legacy_day_summary(date)', 'a5deac1fba5880636f0cda357dadab42', 'f0170fcb61ff1a40c07d532186669212'),
    ('bundle_line_components(uuid)', '799461c5855df161cf48ea3eabf5a4cc', '93ebc0e25991428c5e94a71879bbef41'),
    ('cancel_transfer_request(uuid)', '5f4d42e33c83bfab0b922474babecbb5', 'b12baadcf077487a6c275877275c4750'),
    ('claim_entitlement_vouchers(uuid,jsonb,text)', 'a0215fa3aaaa162772fa6e4dd9ea08bd', 'e6958c6052d3dd8d7ea3a175d614b5da'),
    ('claim_legacy_therapy(uuid,date,uuid,jsonb,text,text)', 'f14136078f691d743b6a0def4a874b09', '3957f56f3ea9dc8df6789371a20add66'),
    ('consultant_notes_for(uuid,uuid)', '9902c96cf8295d11ab4e237dedc60f19', '4f894f72b4af092d7ddd1421b3ab8597'),
    ('credit_package_benefit_preview(uuid,uuid)', 'e0e5dd9571e42c1c2248bc0bc4fea8a9', '4a79692ddfb66374f352c9a6bf9fe565'),
    ('credit_package_effective_rules(uuid)', '8daf32528ae969300ed4bdc9ba13f955', '0b8e865eb1c56e15db885753ffe6f1ee'),
    ('credit_packages_for_store(uuid,date)', '31a4a17f994467786e0cd3202324b578', '85df02046be2b8afc1fa9b685b37aca0'),
    ('customer_overview(uuid)', 'c2dfc1bd43e61699338598bda27e6303', '74e9cddfb699ed78369ee4d01578116e'),
    ('customer_profile_stats(uuid)', 'bca7226679aed8fd44ed9b646a7af27a', '67c5770c7bc0be83899e5fde593fc851'),
    ('customer_purchase_timeline(uuid)', 'fdf6a2c95663ccbac05d7276defdb5dc', 'cb21b1612cc04f5da2e5f07c46f81d0d'),
    ('customer_survey_overview(text,text,integer,integer)', 'b341a5207c6cd72082cc571f1a44b6cc', 'e84eb56b42505e2f8a34e6e7486cf6f9'),
    ('dashboard_alerts_summary()', '13122db6bf0b5c22ea2482e8d28a42af', 'c3a45ca21c315d5cd6bd1bf36108d905'),
    ('dashboard_credit_by_store(text,date,date)', '98157ff3234002bbf0faad93ee746e99', 'fe25ab311d6e3655500dea66c07fa0f1'),
    ('dashboard_credit_spend(text,date,date,uuid)', '4515b567863253ad3cf3e450852aaacf', '540ee810178c15f5c09a6b305bc4bd0d'),
    ('dashboard_summary()', '144fa049474bf7d2932cf5f9bac094be', '96ddc8f96a9bb00a222f11860d2ac221'),
    ('entitlement_voucher_state(uuid)', '80264a4e7fa785b8dca628a41d0145b1', 'f8b6a3a4521e025ed2cd1151cab53ae8'),
    ('exchange_ineligibility_reason(uuid)', '605f70041cd659acbaed2c0347bdbc92', 'c6bebabc448b888a525ef895d5551859'),
    ('exchange_invoice_details(uuid)', '358c33245d0c0bd52e9b96f009b9687b', '9b8f97630794150edae2753469c0a99a'),
    ('invoice_bill_to_source(uuid)', 'd6fae8edb4b1930589c793ed61de8830', 'f46d331ce5410681dfcb73ace9600ca3'),
    ('invoice_legacy_entitlements(uuid)', 'f2db5293a473c1a26582519c80ec6dde', '0cb40c6bf47d07e55dcda725d2e17c0c'),
    ('invoice_revision_history(uuid)', '6111514b5b8396d1304d43f14ae8cf69', '4b5143e1d62e17ae83c1cd7ff507aecf'),
    ('invoice_therapy_summary(uuid)', '52ce8a657627bc919d1580fc6b316e18', 'aa53b9ebea63c57f4b7c87253db8b21a'),
    ('invoice_transferable_benefits(uuid)', '53b7e5631c96fb56273c08354bf8442b', 'e3a4b753d87546a1a73342baf02bee70'),
    ('legacy_qualification_diagnose(uuid,uuid,date)', '70221c452ec55d19f31ae443a984b1a3', 'e46813acdafbf7be537dffaa5fd3237b'),
    ('legacy_reward_options(uuid)', '92a9255cc922d668f885888b208b4560', '5d167cc1ac9d443f4b7d7d2566990770'),
    ('legacy_reward_options_diagnostic(uuid)', '743db28f35ff92291373f58703366cbb', 'f99406c5ee8b9ce1587ed4190239da77'),
    ('legacy_reward_voucher_options(uuid)', 'd4f3df259b63ee561837a3d7890c5f5f', '8728d0ba59ddf0a9e7161ed3483c4618'),
    ('legacy_setup_status()', 'e2f1a408b8f630fd29d870e1f7fd5326', '613421e888aabd2920b27f4194c5ef9b'),
    ('my_assigned_store_id()', 'b4864f1257e48312c4a273f241f8c1c5', 'e07a781a3d7c22742158245b62309993'),
    ('pay_special_with_credit(text,uuid,uuid,numeric,uuid)', 'dfbae74ac655ea4e711db90ea9adacfc', '5496ea7f657d49629653defc905c88f2'),
    ('premium_bundle_benefit_preview(uuid,uuid)', '3e0de91e323105ef941c434d0bdeacdc', 'ef66cef34d170f24b642eef3521f402c'),
    ('premium_bundles_for_store(uuid,date)', '0b8b5b2a16747e6a12c217098a78ff7e', 'e8de14d2264ec3e551df0f52bb6a6524'),
    ('products_available_as_special()', '8e76dcac282b039735ced84fd2707c93', '0e39e3af72fe1f88bffdba9f50a61c2f'),
    ('promotion_original_total(uuid,uuid)', '9712b8d78d474896aac89081469afd30', '2480074e2b77e313b052cc225493087c'),
    ('record_document_send(text,text,text,uuid,uuid,text,text,text,text)', 'd4b4aff765a161e58f31fda2d2e37ef8', 'b602db515c9a685bf6fe642eb312b4ab'),
    ('report_customer_sources(date,date)', '1b54e0dd1ea7b215c396ca87c760555e', 'de5b160f34a49ff254c8f93cdc0f5106'),
    ('resolve_tiktok_physical_return(uuid,boolean,text,text)', '844cf27fde0936e93f20b3a05ad8dfe7', '12ae6689e864b6374f3d5090f5fccb4b'),
    ('return_stock_loan(uuid,jsonb,text,uuid)', '978c886b03ccae32d48de8bc78667975', 'c79caeb845c31b3032f90df3d0e01778'),
    ('special_docs_awaiting_fulfilment()', 'ff0f89048581abdfac941fdf84e39514', 'aed7e3b24ff192cbe09935c5e7488881'),
    ('special_product_availability(uuid)', '57d4d5e52f787dc71d957c4ba9276045', '467b0d480d36f0535dd39bac1e5095a3'),
    ('store_commission_staff(uuid)', '7aca1c0300eb821fa8b825761c211f98', '5debdc440bd1b3750e0a194c184f8f92'),
    ('therapy_customer_detail(uuid)', 'fcbedaa5ef6f2f56c3271d3c6d6690ec', '80abbc0a7b61f91c0a4248f9b18d8f4e'),
    ('therapy_customer_summary(text,integer,integer,boolean)', '6bb0f3b4b81882f51ee4f4e115391779', '55b69d8530418f74416bce23e3bdaa66'),
    ('therapy_service_catalogue(uuid,boolean)', 'd4bcd45afab45f2a63a18650c2b5412d', '3b1ffd4f7e1553b518ed65cb9eb6e43c'),
    ('tiktok_negative_stock_alerts()', '7415c756855445f041c5a616de345573', 'e220e1441d930f34f58163ff5993db97'),
    ('upsert_consultant_survey(uuid,text,text,text,text,boolean,boolean,boolean,boolean,text,uuid)', '1389c4734bffe9b21dfbfad35a17c38a', 'd653a0edddef3023b7dac7b0f97e0964')
  ) x(fn, before_md5, after_md5)
  loop
    v := md5(pg_get_functiondef(to_regprocedure('public.' || r.fn)));
    if v <> r.after_md5 then v_bad := concat_ws('; ', v_bad, r.fn || ' ' || v); end if;
  end loop;
  if v_bad is not null then
    raise exception '406: installed with md5s other than the tested ones: %', v_bad; end if;
  if (select array_agg(coalesce(p.proacl::text, '') order by p.oid::regprocedure::text)
        from pg_proc p where p.pronamespace = 'public'::regnamespace
         and p.oid::regprocedure::text = any (array_append(v_fns, 'current_user_role()')))
     is distinct from v_acl then
    raise exception '406: the grants of the patched functions changed'; end if;
  if (select p.qual from pg_policies p where p.schemaname = 'public' and p.tablename = 'profiles'
        and p.policyname = 'read profiles') is distinct from c_read_profiles_after then
    raise exception '406: "read profiles" is not as tested'; end if;

  -- ── Grants, by the catalogue ─────────────────────────────────────────────
  foreach v in array array['require_active_staff(text[])', 'require_store_access(uuid)',
    'write_audit(text,uuid,text,jsonb,jsonb)', 'auth_email_user_state(text)',
    'auth_email_reserve(text,text,text)', 'auth_email_record_outcome(uuid,text,text,text,integer,text)',
    'commission_outside_rebase_scope()', 'commission_totals_reconciliation()',
    'preview_commission_rebase_effect(date,date)', 'validate_bundle_voucher_selection(uuid,uuid,jsonb)'] loop
    if has_function_privilege('anon', 'public.' || v, 'execute')
       or has_function_privilege('authenticated', 'public.' || v, 'execute')
       or not has_function_privilege('service_role', 'public.' || v, 'execute') then
      raise exception '406: public.% is not the service role''s alone', v; end if;
  end loop;
  if has_function_privilege('anon', 'public.record_document_printed(text,uuid)', 'execute')
     or not has_function_privilege('authenticated', 'public.record_document_printed(text,uuid)', 'execute')
     or not has_function_privilege('service_role', 'public.record_document_printed(text,uuid)', 'execute') then
    raise exception '406: public.record_document_printed is not signed-in logins'' and the service role''s alone'; end if;
  if not has_function_privilege('authenticated', 'public.current_user_role()', 'execute') then
    raise exception '406: current_user_role() is no longer reachable by signed-in logins; every policy reading it would fail'; end if;

  -- ── Behaviour, switching role (nothing is printed, no row changes) ───────
  -- A signed-in login with no staff profile.
  perform set_config('request.jwt.claims',
    json_build_object('sub', gen_random_uuid(), 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  if public.current_user_role() is not null then
    raise exception '406: a login with no profile has a role'; end if;
  foreach v in array array[
    'select count(*) from public.customer_survey_overview(null, ''all'', 1, 0)',
    'select count(*) from public.consultant_notes_for(null, null)',
    'select count(*) from public.active_affiliates_for_picker()',
    'select public.record_document_send(''invoice'', ''406-CHECK'', ''whatsapp'')',
    'select public.upsert_consultant_survey(gen_random_uuid())',
    'select public.write_audit(''invoices'', null, ''406_check'', null, null)',
    'select public.auth_email_user_state(''check@tests.invalid'')'] loop
    begin
      execute v;
      raise exception '406: a login with no profile was not refused: %', v;
    exception when insufficient_privilege then null;
    end;
  end loop;
  execute 'reset role';
  -- The server: the service role, as the website orders and Edge Functions.
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  execute 'set local role service_role';
  perform public.credit_package_effective_rules(null);
  perform count(*) from public.store_commission_staff(null);
  execute 'reset role';
  -- An active Owner, when there is one, still passes.
  select p.id into v_owner from public.profiles p
   where p.role = 'owner' and p.is_active and p.deleted_at is null
     and coalesce(p.invitation_status, 'accepted') = 'accepted'
   order by p.created_at limit 1;
  if v_owner is not null then
    perform set_config('request.jwt.claims',
      json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    v_role := public.current_user_role();
    if v_role is distinct from 'owner' then
      raise exception '406: an active Owner has no role'; end if;
    -- Through a guarded function, as the pages call it (the check itself is
    -- the server's alone).
    perform count(*) from public.customer_survey_overview(null, 'all', 1, 0);
    perform public.dashboard_summary();
    execute 'reset role';
  end if;
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);

  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $mig$;
