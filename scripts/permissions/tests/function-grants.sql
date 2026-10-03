-- Functions are not endpoints by default (339).
--
-- Three things must hold on any database the application runs against, and all
-- three are read from the catalogue rather than from the migration's own
-- bookkeeping. PostgreSQL still grants EXECUTE on every new function to PUBLIC
-- and that built-in default cannot be withdrawn (see 339), so this test is
-- what enforces the convention: add a function without revoking it from anon
-- and the first check below names it.
--
-- Disposable local database only; this test writes nothing.
\set ON_ERROR_STOP on
do $$
declare
  v_public text[] := array['survey_link_info','submit_health_survey','active_customer_source_options',
                           'public_affiliate_referral_info','affiliate_referral_signup'];
  -- Reached only from inside another SECURITY DEFINER function, which runs as
  -- the owner. A staff member calling any of these directly could earn a
  -- commission twice, approve their own transfer, or burn an invoice number.
  v_internal text[] := array['approve_transfer','approve_transfer_multi','earn_invoice_commission',
                             'earn_staff_commission','earn_credit_package_commission','earn_premium_bundle_commission',
                             'reverse_invoice_commission','reverse_staff_commission','refund_credit_purchase',
                             'refund_credit_funded_item','refund_invoice_line','sell_credit_package_with_vouchers',
                             'sell_premium_bundle','consume_customer_credit','deduct_invoice_stock',
                             'restore_invoice_stock','revoke_unclaimed_entitlement_vouchers',
                             'revoke_affiliate_reward_vouchers','tiktok_adjust_product_stock',
                             'tiktok_adjust_voucher_stock','merge_customer_records','next_invoice_no',
                             'issue_credit_lines_for_invoice','lock_settled_invoice','correct_invoice_created_by',
                             -- 357/358: part-payment commission and staff-sales credit
                             'sync_instalment_commissions','trg_sync_instalment_commissions',
                             'invoice_instalment_commission_targets','invoice_instalment_commission_active',
                             'invoice_affiliate_commission_preview','invoice_package_commission_preview',
                             'invoice_sales_credit_split','invoice_staff_sales_ledger','commission_unpaid_amount',
                             -- 356: released credit follows its lot
                             'credit_lot_chain','credit_lot_current','trim_released_paid_credit',
                             'reclaim_released_credit_of_removed_lines','refuse_settled_credit_line_raise',
                             -- 359: package coverage and the refund rule's "used"
                             'therapy_services_coverage','therapy_unit_consumed',
                             -- 360: what stops a voucher unit switching back
                             'therapy_switch_back_blocker',
                             -- 361: the products a promotion line holds
                             'invoice_line_stock_products',
                             -- 362: a correction settles the therapy of the lines it changes
                             'create_purchased_therapy_for_invoice','therapy_units_before_correction',
                             'settle_corrected_therapy_units','issue_therapy_of_corrected_lines',
                             -- 367: when a TikTok settlement row reconciles
                             'tiktok_settlement_row_reconciled',
                             -- 368: which TikTok settlement lines were left out at confirmation
                             'tiktok_settlement_left_out_rows',
                             -- 370: the event rules behind tickets, guests and event sales
                             'event_is_staff','event_can_run','event_ticket_price','event_ticket_line_check',
                             'event_sync_ticket_line','event_sync_ticket_names','trg_event_ticket_line_removed',
                             'trg_event_guests_follow_invoice','event_invoice_membership',
                             'event_candidate_invoices','event_day_load','event_summary',
                             'event_ticket_people_given','event_ticket_line_refunded','event_ticket_line_money',
                             'event_ticket_guests_follow_line','trg_event_guests_follow_refund','event_ticket_price_date',
                             -- 372: website orders are handed in by the edge function only
                             'web_order_uuid','web_order_phone_customers','web_order_customer','web_order_people',
                             'web_order_make_invoice','web_order_rename_people','web_order_paid','web_order_names',
                             -- 378: who counts as staff for affiliate account claims
                             'affiliate_claim_staff',
                             -- 380: staff-link orders, the website's sync and staff list, and their rules
                             'web_order_door','web_order_sync','web_order_staff','web_order_door_method_name',
                             'web_order_seller','web_order_door_review','web_order_invoice_methods',
                             'web_order_invoice_people','web_order_sync_people','web_order_link_target',
                             'web_order_link_summary','web_order_person_email','web_order_number_people',
                             'web_order_hand_invoices','web_order_can_link',
                             -- 381: the nudge the database's cron job sends
                             'web_order_sync_ping',
                             -- 384: the rules of an invoice line's one Discount
                             'invoice_line_discount_kind','invoice_line_discount_for','invoice_birthday_check',
                             'invoice_birthday_lines_check','invoice_line_discount_take','invoice_line_discount_write',
                             'invoice_line_discount_rebase','invoice_line_discount_only','trg_voucher_discount_category',
                             'trg_invoice_item_line_discount_reason'];
  bad text; n int;
begin
  -- 1. Nothing outside the five signed-out endpoints is callable with the anon
  --    key, which ships in the browser bundle.
  select string_agg(p.proname, ', ' order by p.proname) into bad
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prokind = 'f'
     and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')
     and has_function_privilege('anon', p.oid, 'execute')
     and not (p.proname = any(v_public));
  if bad is not null then
    raise exception 'FAIL: callable by anon outside the public allowlist: %', bad; end if;

  -- 2. The five are still reachable, or the public survey and the referral
  --    landing page stop working for signed-out visitors.
  select string_agg(x, ', ') into bad from unnest(v_public) x
   where not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                      where n.nspname = 'public' and p.proname = x
                        and has_function_privilege('anon', p.oid, 'execute'));
  if bad is not null then raise exception 'FAIL: signed-out endpoint no longer reachable: %', bad; end if;

  -- 3. Privileged internals are endpoints for nobody.
  select string_agg(p.proname, ', ' order by p.proname) into bad
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = any(v_internal)
     and (has_function_privilege('anon', p.oid, 'execute')
          or has_function_privilege('authenticated', p.oid, 'execute'));
  if bad is not null then
    raise exception 'FAIL: internal helper is callable by a client role: %', bad; end if;

  -- 4. Anything the database evaluates as the person asking — a row-level
  --    security policy, a check constraint, a column default, an index
  --    expression — must stay reachable by staff. user_has_store_access is in
  --    the SELECT policy of nearly every table: revoking it does not lock down
  --    an endpoint, it empties the application for everyone.
  select coalesce(string_agg(t, ' '), '') into bad from (
    select coalesce(pol.qual,'')||' '||coalesce(pol.with_check,'') t from pg_policies pol where pol.schemaname='public'
    union all select pg_get_constraintdef(c.oid) from pg_constraint c join pg_namespace n2 on n2.oid=c.connamespace where n2.nspname='public'
    union all select pg_get_expr(d.adbin, d.adrelid) from pg_attrdef d join pg_class c on c.oid=d.adrelid
      join pg_namespace n2 on n2.oid=c.relnamespace where n2.nspname='public'
  ) x;
  select string_agg(p.proname, ', ' order by p.proname) into bad
    from pg_proc p join pg_namespace n2 on n2.oid = p.pronamespace
   where n2.nspname = 'public' and p.prokind = 'f'
     and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')
     and bad ~ ('\m' || p.proname || '\M')
     and not has_function_privilege('authenticated', p.oid, 'execute');
  if bad is not null then
    raise exception 'FAIL: a function the database evaluates as the caller is not reachable by staff, so policies and constraints will fail: %', bad; end if;

  -- 5. No two functions of one name take the same parameter names. The API
  --    server picks an overload by parameter names alone, whoever may execute
  --    it, so such a pair fails every call to that name (364: every transfer an
  --    Owner or Manager created failed this way). Revoking one does not help.
  select string_agg(proname || '(' || args || ')', '; ') into bad from (
    select p.proname,
           coalesce((select string_agg(nm, ',' order by nm)
                       from unnest(p.proargnames) with ordinality a(nm, i)
                      where coalesce(p.proargmodes[i]::text, 'i') in ('i','b','v')), '') args
      from pg_proc p join pg_namespace n2 on n2.oid = p.pronamespace
     where n2.nspname = 'public' and p.prokind = 'f'
       and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')
  ) f group by proname, args having count(*) > 1;
  if bad is not null then
    raise exception 'FAIL: the API cannot choose between functions with the same parameter names: %', bad; end if;

  -- 6. The seven-argument create_invoice stays gone (386). Granted to staff,
  --    it wrote a discount with no reason and none of 385's line rules; only
  --    the default of the current create_invoice's eighth argument kept calls
  --    from reaching it. Revoking it is not enough: while it exists, a patch
  --    that picks "the" create_invoice by name can patch it instead (302).
  if to_regprocedure('public.create_invoice(uuid,uuid,uuid,jsonb,numeric,text,uuid)') is not null then
    raise exception 'FAIL: the legacy create_invoice(uuid,uuid,uuid,jsonb,numeric,text,uuid) is back; 386 dropped it'; end if;

  -- 7. The seven-argument record_document_send stays gone (388), for the same
  --    reason. Granted to staff, it was an older copy of the send log's
  --    writer; only the defaults of the current one's later arguments kept
  --    calls from reaching it.
  if to_regprocedure('public.record_document_send(text,text,text,uuid,uuid,text,text)') is not null then
    raise exception 'FAIL: the legacy record_document_send(text,text,text,uuid,uuid,text,text) is back; 388 dropped it'; end if;

  -- 8. The three-argument promotion_selections_topup stays gone (390), for
  --    the same reason. It priced bundle top-ups by the old rules; only the
  --    default of the current one's p_is_member kept calls from reaching it.
  --    Re-running 21, 21b or UPGRADE_to_current.sql would bring it back.
  if to_regprocedure('public.promotion_selections_topup(uuid,uuid,jsonb)') is not null then
    raise exception 'FAIL: the legacy promotion_selections_topup(uuid,uuid,jsonb) is back; 390 dropped it'; end if;

  select count(*) into n from pg_proc p join pg_namespace n2 on n2.oid = p.pronamespace
   where n2.nspname = 'public' and p.prokind = 'f'
     and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')
     and has_function_privilege('authenticated', p.oid, 'execute');
  raise notice 'PASS: only the 5 signed-out endpoints are callable by anon; % application functions remain callable by staff; the named privileged internals are callable by neither; no two functions share a name and parameter names; the legacy seven-argument create_invoice and record_document_send and three-argument promotion_selections_topup are gone', n;
end $$;
