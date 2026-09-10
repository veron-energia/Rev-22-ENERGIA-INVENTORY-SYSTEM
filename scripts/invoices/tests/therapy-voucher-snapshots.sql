-- Run after the invoice migrations, 240-245, and 251 in the isolated test DB.
-- All fixtures and operations roll back; this script performs no connection setup.
begin;
do $$
#variable_conflict use_variable
declare owner_id uuid:=gen_random_uuid(); store_id uuid; buyer_id uuid; recipient_id uuid;
 original_service uuid; changed_service uuid; voucher_id uuid; bundle_id uuid; method_id uuid;
 invoice_id uuid; item_id uuid; payment_id uuid; benefit_id uuid; original_voucher uuid; original_issue uuid;
 moved_benefit uuid; moved_voucher uuid; moved_issue uuid; request_id uuid:=gen_random_uuid();
 original_snapshot jsonb; result jsonb; rights record; candidate record; count_before integer;
 unknown_original uuid; unknown_replacement uuid; unknown_benefit uuid; transfer_id uuid;
begin
 insert into auth.users(id,email) values(owner_id,'voucher-snapshots@tests.invalid');
 insert into public.profiles(id,full_name,email,role) values(owner_id,'Voucher Snapshot Owner','voucher-snapshots@tests.invalid','owner');
 perform set_config('request.jwt.claim.sub',owner_id::text,true);
 insert into public.stores(name,code,country_code) values('Voucher Snapshot Tests','TV-SNAP','SG') returning id into store_id;
 insert into public.customers(full_name,phone) values('Voucher Snapshot Buyer','+6591238892') returning id into buyer_id;
 insert into public.customers(full_name,phone) values('Voucher Snapshot Recipient','+6591238893') returning id into recipient_id;
 insert into public.payment_methods(name) values('Voucher Snapshot Cash') returning id into method_id;
 insert into public.therapy_services(service_code,name,standard_price,duration_minutes,is_active)
  values('TV-ORIGINAL','Original service',20,30,true) returning id into original_service;
 insert into public.therapy_services(service_code,name,standard_price,duration_minutes,is_active)
  values('TV-CHANGED','Changed catalogue service',90,90,true) returning id into changed_service;
 insert into public.vouchers(name,code,qty_type,reward_eligible)
  values('Frozen therapy voucher','TV-SNAP','limited',true) returning id into voucher_id;
 insert into public.voucher_store_stock(voucher_id,store_id,current_qty) values(voucher_id,store_id,100);
 insert into public.voucher_store_prices(voucher_id,store_id,selling_price,available_at_store) values(voucher_id,store_id,20,true);
 perform public.upsert_therapy_voucher_definition(voucher_id,
  jsonb_build_array(jsonb_build_object('kind','fixed','service_id',original_service,'quantity',2)),
  'months',1,'unrestricted',1,null,'Original terms');
 insert into public.premium_bundles(name,customer_payment_amount,paid_credit_amount,free_voucher_qty,grants_reward)
  values('Frozen voucher bundle',140,100,2,true) returning id into bundle_id;
 insert into public.premium_bundle_stores(bundle_id,store_id) values(bundle_id,store_id);
 insert into public.premium_bundle_vouchers(bundle_id,voucher_id) values(bundle_id,voucher_id);
 invoice_id:=public.create_invoice(store_id,buyer_id,null,jsonb_build_array(jsonb_build_object(
  'kind','premium_bundle','premium_bundle_id',bundle_id,'quantity',1,
  'voucher_selection',jsonb_build_array(jsonb_build_object('voucher_id',voucher_id,'quantity',2)))));
 perform public.record_invoice_payment(invoice_id,jsonb_build_array(jsonb_build_object('payment_method_id',method_id,'amount',140)),gen_random_uuid());
 select it.id into item_id from public.invoice_items it where it.invoice_id=invoice_id;
 select p.id into payment_id from public.invoice_payments p where p.invoice_id=invoice_id;
 select b.id,b.reward_voucher_id into benefit_id,original_voucher from public.invoice_benefit_values b
  where b.invoice_item_id=item_id and b.reward_voucher_id is not null;
 select id into original_issue from public.therapy_voucher_issues where reward_voucher_id=original_voucher;
 if original_issue is null then raise exception 'Original issuance did not snapshot therapy rights'; end if;
 -- A historical expiry makes any reset to the replacement date unmistakable.
 update public.therapy_voucher_issues set issued_at='2020-01-01 00:00:00+08',valid_until='2020-01-31' where id=original_issue;
 select to_jsonb(t) into original_snapshot from public.therapy_voucher_issues t where t.id=original_issue;

 perform public.refund_invoice_recorded(invoice_id,
  jsonb_build_array(jsonb_build_object('invoice_item_id',item_id,'amount',20,'benefits',jsonb_build_array(jsonb_build_object('benefit_id',benefit_id,'amount',20)))),
  jsonb_build_array(jsonb_build_object('payment_id',payment_id,'amount',20)),'[]','One original unused voucher unit',request_id);
 select * into rights from public.customer_therapy_voucher_rights(buyer_id) where reward_voucher_id=original_voucher;
 if rights.units<>1 or rights.sessions_total<>4 or rights.sessions_remaining<>2 then
  raise exception 'Partial refund did not reduce current rights while preserving the original total: %',row_to_json(rights); end if;
 if (select to_jsonb(t) from public.therapy_voucher_issues t where t.id=original_issue) is distinct from original_snapshot then
  raise exception 'Partial refund rewrote the original issue snapshot'; end if;
 if not exists(select 1 from public.therapy_voucher_unit_changes a where a.reward_voucher_id=original_voucher
  and a.previous_units=2 and a.new_units=1 and a.previous_available_sessions=4 and a.new_available_sessions=2) then
  raise exception 'Partial rights reduction has no audit record'; end if;
 if not exists(select 1 from public.therapy_customer_entitlements(buyer_id) e
  where e.source_kind='voucher' and e.source_id=original_voucher and e.remaining=2 and not e.is_usable) then
  raise exception 'Combined entitlement model did not read the reduced, expired rights'; end if;
 select count(*) into count_before from public.therapy_voucher_unit_changes where reward_voucher_id=original_voucher;
 perform public.refund_invoice_recorded(invoice_id,
  jsonb_build_array(jsonb_build_object('invoice_item_id',item_id,'amount',20,'benefits',jsonb_build_array(jsonb_build_object('benefit_id',benefit_id,'amount',20)))),
  jsonb_build_array(jsonb_build_object('payment_id',payment_id,'amount',20)),'[]','One original unused voucher unit',request_id);
 if (select count(*) from public.therapy_voucher_unit_changes where reward_voucher_id=original_voucher)<>count_before then
  raise exception 'Refund replay duplicated a rights reduction'; end if;

 -- Aggregate session usage cannot prove which voucher unit is entirely unused.
 update public.therapy_voucher_issues set sessions_used=1 where id=original_issue;
 begin
  perform public.transfer_invoice_unused_benefit(benefit_id,recipient_id,store_id,'Cannot move consumed rights',gen_random_uuid());
  raise exception 'Consumed voucher transfer accepted';
 exception when others then if sqlerrm not like '%unit-level consumption%' then raise; end if; end;
 begin
  perform public.refund_invoice_recorded(invoice_id,
   jsonb_build_array(jsonb_build_object('invoice_item_id',item_id,'amount',20,'benefits',jsonb_build_array(jsonb_build_object('benefit_id',benefit_id,'amount',20)))),
   jsonb_build_array(jsonb_build_object('payment_id',payment_id,'amount',20)),'[]','Cannot refund ambiguous consumed units',gen_random_uuid());
  raise exception 'Consumed voucher refund accepted';
 exception when others then if sqlerrm not like '%unit-level consumption%' then raise; end if; end;
 if (select status from public.customer_reward_vouchers where id=original_voucher)<>'held'
  or (select count(*) from public.invoice_refunds r where r.invoice_id=invoice_id)<>1 then
  raise exception 'Failed consumed-unit operation changed voucher or refund history'; end if;
 update public.therapy_voucher_issues set sessions_used=0 where id=original_issue;

 -- Today's definition deliberately differs in service, count, validity and terms.
 perform public.upsert_therapy_voucher_definition(voucher_id,
  jsonb_build_array(jsonb_build_object('kind','fixed','service_id',changed_service,'quantity',5)),
  'months',12,'unrestricted',1,null,'New catalogue terms');
 result:=public.transfer_invoice_unused_benefit(benefit_id,recipient_id,store_id,'Correct the unused voucher recipient',gen_random_uuid());
 moved_benefit:=(result->>'benefit_id')::uuid;
 select reward_voucher_id into moved_voucher from public.invoice_benefit_values where id=moved_benefit;
 select id into moved_issue from public.therapy_voucher_issues where reward_voucher_id=moved_voucher;
 if not exists(select 1 from public.therapy_voucher_issues t where t.id=moved_issue
  and t.source_issue_id=original_issue and t.customer_id=recipient_id and t.units=1 and t.sessions_total=2
  and t.definition_snapshot=original_snapshot->'definition_snapshot'
  and t.definition_version=(original_snapshot->>'definition_version')::int
  and t.valid_until='2020-01-31' and t.issued_at='2020-01-01 00:00:00+08') then
  raise exception 'Transfer used current catalogue terms, quantity or expiry'; end if;
 if (select to_jsonb(t) from public.therapy_voucher_issues t where t.id=original_issue) is distinct from original_snapshot then
  raise exception 'Transfer rewrote the original issue snapshot'; end if;
 select * into rights from public.customer_therapy_voucher_rights(recipient_id) where reward_voucher_id=moved_voucher;
 if rights.sessions_remaining<>2 or rights.is_usable or not rights.is_expired then raise exception 'Transferred expired voucher became usable'; end if;

 perform public.refund_invoice_recorded(invoice_id,
  jsonb_build_array(jsonb_build_object('invoice_item_id',item_id,'amount',20,'benefits',jsonb_build_array(jsonb_build_object('benefit_id',moved_benefit,'amount',20)))),
  jsonb_build_array(jsonb_build_object('payment_id',payment_id,'amount',20)),'[]','Refund transferred unused unit',gen_random_uuid());
 if (select sessions_remaining from public.customer_therapy_voucher_rights(recipient_id) where reward_voucher_id=moved_voucher)<>0 then
  raise exception 'Fully refunded transferred voucher retains rights'; end if;
 perform public.cancel_invoice_recorded(invoice_id,'Cancel remaining unused bundle credit',gen_random_uuid());
 perform public.reopen_invoice(invoice_id,'Reinstate only the refunded original grants',gen_random_uuid());
 perform public.record_invoice_payment(invoice_id,jsonb_build_array(jsonb_build_object('payment_method_id',method_id,'amount',40)),gen_random_uuid());
 if (select count(*) from public.invoice_reopen_vouchers q where q.invoice_id=invoice_id and q.applied_at is not null)<>2 then
  raise exception 'Reopening did not create both traced original-unit replacements'; end if;
 for candidate in select q.replacement_voucher_id,b.reward_voucher_id source_voucher
  from public.invoice_reopen_vouchers q join public.invoice_benefit_values b on b.id=q.benefit_id where q.invoice_id=invoice_id loop
  if not exists(select 1 from public.therapy_voucher_issues child join public.therapy_voucher_issues parent on parent.id=child.source_issue_id
   where child.reward_voucher_id=candidate.replacement_voucher_id and parent.reward_voucher_id=candidate.source_voucher
   and child.definition_snapshot=original_snapshot->'definition_snapshot'
   and child.valid_until='2020-01-31' and child.sessions_per_unit=2 and child.units=1
   and child.customer_id=parent.customer_id and child.issued_at=parent.issued_at) then
   raise exception 'Reopening did not carry the exact original service rights/expiry/recipient'; end if;
 end loop;

 -- A replacement of an unrecorded legacy voucher must stay unrecorded even
 -- when the catalogue now has a complete definition. No inferred backfill.
 perform public.clear_therapy_voucher_definition(voucher_id);
 insert into public.customer_reward_vouchers(customer_id,voucher_id,store_id,quantity,status,issued_by,source_type)
  values(buyer_id,voucher_id,store_id,1,'held',owner_id,'legacy') returning id into unknown_original;
 perform public.upsert_therapy_voucher_definition(voucher_id,
  jsonb_build_array(jsonb_build_object('kind','fixed','service_id',changed_service,'quantity',5)));
 insert into public.invoice_benefit_values(invoice_id,invoice_item_id,reward_voucher_id,paid_value,granted_value,evidence,created_by)
  values(invoice_id,item_id,unknown_original,20,1,'Synthetic legacy source without therapy rights',owner_id) returning id into unknown_benefit;
 insert into public.invoice_benefit_transfers(invoice_id,source_benefit_id,customer_id,store_id,transferred_value,request_id,request_hash,reason,before_snapshot,created_by)
  values(invoice_id,unknown_benefit,recipient_id,store_id,1,gen_random_uuid(),'synthetic-unknown-source',
   'Trace a legacy source without assuming service rights','{}',owner_id) returning id into transfer_id;
 insert into public.customer_reward_vouchers(customer_id,voucher_id,store_id,quantity,status,issued_by,source_type,source_id)
  values(recipient_id,voucher_id,store_id,1,'held',owner_id,'invoice_benefit_transfer',transfer_id) returning id into unknown_replacement;
 if exists(select 1 from public.therapy_voucher_issues where reward_voucher_id=unknown_replacement) then
  raise exception 'Replacement of an unrecorded legacy grant received guessed current rights'; end if;
 if not exists(select 1 from public.therapy_customer_entitlements(recipient_id) e
  where e.source_id=unknown_replacement and e.eligibility='unrecorded' and not e.is_usable) then
  raise exception 'Unrecorded replacement not shown as pending review'; end if;
 if has_function_privilege('authenticated','public.snapshot_therapy_voucher_issue(uuid,boolean)','execute')
  or has_function_privilege('authenticated','public.snapshot_therapy_voucher_issue_current_catalogue(uuid,boolean)','execute') then
  raise exception 'Internal snapshot helpers are callable outside the audited review/issuance paths'; end if;
 raise notice 'PASS: original therapy voucher terms and expiry survive transfer/reopening; partial refunds reduce current rights with audit and retry safety; ambiguous consumption and missing historical rights stay pending';
end $$;
rollback;
