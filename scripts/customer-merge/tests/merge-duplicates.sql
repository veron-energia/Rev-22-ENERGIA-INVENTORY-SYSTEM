-- Two records of the same person become one.
--
-- Forty-four tables reference customers. The merge repoints them from the
-- catalogue rather than a hand-written list, carries credit balances into the
-- surviving wallet, and refuses the two cases a script must not decide: two
-- affiliate records, and a commission that has one record as buyer and the
-- other as referrer.
--
-- Since 486 the merge also refuses to retire the record that holds the
-- affiliate record into a record that has neither a portal login nor an
-- affiliate record. That is checked on this pair, and found to change
-- nothing, before the record kept is given a portal login (no affiliate
-- record of its own); then the duplicate's affiliate record is carried
-- across as before. That check is its own (PASS or FAIL: 486), and fails
-- where 486 is not in; the merge it then lets through is undone, so the rest
-- runs as before.
--
-- That portal login is a shape only this test makes: an affiliate_accounts
-- row with no affiliate_id, on a record with no affiliate record. The app's
-- two ways to make a login (complete_affiliate_onboarding and
-- resolve_affiliate_account_claim) find or make the record's affiliate
-- record first and name it, so the record kept would hold an affiliate
-- record too and this merge would stop as two affiliate records
-- (production, 2 Nov 2026: 86 logins, every one naming its own record's
-- affiliate record). The row goes in with session_replication_role =
-- replica, which turns off the triggers for that one insert: the welcome
-- WhatsApp's and the foreign-key checks (the row meets its keys). The merge
-- carries the affiliate record to that record only because 486 lets a
-- record kept with a login take the duplicate's affiliate record (486's
-- first NOT COVERED); closing that gap means rebuilding this suite again.
--
-- Disposable database only; everything is rolled back. Every name, phone and
-- email below is invented: ACMA fictional numbers (+61 2 5550 4870 and
-- 4871) and .invalid addresses.
begin;
-- 486: what a refused merge must leave as it was: every row naming either
-- record (every column referencing customers), the two records themselves,
-- and the audit log.
create function pg_temp.mrg_state(a uuid, b uuid) returns text language plpgsql as
$f$declare r record; v text; acc text := '';
begin
  for r in select c.relname as tbl, att.attname as col
             from pg_constraint k
             join pg_class c on c.oid = k.conrelid and c.relkind = 'r'
             join pg_attribute att on att.attrelid = k.conrelid and att.attnum = any (k.conkey)
             join pg_class f on f.oid = k.confrelid
             join pg_namespace ns on ns.oid = c.relnamespace
            where k.contype = 'f' and f.relname = 'customers' and ns.nspname = 'public'
            order by 1, 2 loop
    execute format('select coalesce(md5(string_agg(x, ''|'' order by x)), ''-'') from (select to_jsonb(t)::text x from public.%I t where %I in ($1, $2)) s',
                   r.tbl, r.col) into v using a, b;
    acc := acc || r.tbl || '.' || r.col || '=' || v || ' ';
  end loop;
  return acc || 'customers=' || (select md5(string_agg(to_jsonb(c)::text, '|' order by c.id)) from public.customers c where c.id in (a, b))
             || ' audit=' || (select count(*) from public.audit_logs);
end$f$;
do $$
declare own uuid:=gen_random_uuid(); st uuid; keep uuid; dup uuid; other uuid; pm uuid;
 prod uuid; v1 uuid; inv uuid; lot uuid; r jsonb; n bigint; rq uuid:=gen_random_uuid();
 keep_wallet uuid; dup_wallet uuid; dup_aff uuid; v486 text;
begin
 insert into auth.users(id,email) values(own,'mrg@tests.invalid');
 insert into profiles(id,full_name,email,role) values(own,'Owner','mrg@tests.invalid','owner');
 perform set_config('request.jwt.claim.sub',own::text,true);
 insert into stores(name,code,country_code) values('MRG Store','MRG','SG') returning id into st;
 insert into payment_methods(name) values('MRG Cash') returning id into pm;
 insert into products(name,sku,product_type) values('MRG Item','MRG-1','own') returning id into prod;
 insert into store_inventory(store_id,product_id,current_qty) values(st,prod,50);
 perform set_product_prices(st,prod,100,100,'available');
 insert into vouchers(name,code,voucher_kind,qty_type,selling_price,is_active)
  values('MRG Facial','MRGF','normal','limited',50,true) returning id into v1;
 insert into voucher_store_stock(voucher_id,store_id,current_qty) values(v1,st,50);

 insert into customers(full_name,phone) values('Same Person','+61255504870') returning id into keep;
 insert into customers(full_name,phone) values('Same Person (dup)','+61255504870') returning id into dup;
 insert into customers(full_name,phone,referred_by) values('Referred By Dup','+61255504871',dup) returning id into other;

 -- the duplicate holds real things
 inv:=create_invoice(st,dup,null,jsonb_build_array(jsonb_build_object('kind','product','product_id',prod,'quantity',1)));
 perform pay_invoice(inv,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',100)));
 lot:=grant_customer_credit(dup,'paid',300,'manual',null,st,sg_today(),null,'dup credit',null,null,own,null);
 insert into customer_reward_vouchers(customer_id,voucher_id,store_id,quantity,status,issued_by,notes)
  values(dup,v1,st,2,'held',own,'held by the duplicate');
 -- and so does the keeper, so both have wallets
 perform grant_customer_credit(keep,'paid',100,'manual',null,st,sg_today(),null,'keep credit',null,null,own,null);

 select id into keep_wallet from customer_credit_wallets where customer_id=keep;
 select id into dup_wallet  from customer_credit_wallets where customer_id=dup;
 if keep_wallet is null or dup_wallet is null then raise exception 'Both should have a wallet for this test'; end if;

 -- ---- the preview describes it -------------------------------------------
 r:=preview_customer_merge(keep,dup);
 if not (r->>'can_merge')::boolean then
  raise exception 'A clean merge was reported as blocked: %', r->'blocking'; end if;
 if (r->'moving'->>'invoices')::int<>1 then raise exception 'The invoice was not counted'; end if;
 if (r->'moving'->>'credit_remaining')::numeric<>300 then raise exception 'The credit was not counted'; end if;
 if (r->'moving'->>'vouchers')::int<>2 then raise exception 'The vouchers were not counted'; end if;
 if (r->'moving'->>'referred_customers')::int<>1 then raise exception 'The referred customer was not counted'; end if;

 -- ---- two affiliate records must stop it ----------------------------------
 declare a1 uuid; a2 uuid; begin
  insert into customer_affiliates(customer_id,status,store_id,activated_at) values(keep,'active',st,now()) returning id into a1;
  insert into customer_affiliates(customer_id,status,store_id,activated_at) values(dup,'active',st,now()) returning id into a2;
  if (preview_customer_merge(keep,dup)->>'can_merge')::boolean then
   raise exception 'Two affiliate records did not block the merge'; end if;
  begin
   perform merge_customer_records(keep,dup,'try anyway',gen_random_uuid());
   raise exception 'The merge ran with two affiliate records';
  exception when others then
   if sqlerrm not like '%needs review first%' then raise; end if; end;
  -- resolve it the way a person would, keeping the duplicate's record so the
  -- merge has to carry it across
  delete from customer_affiliates where id=a1;
  dup_aff:=a2;
 end;

 -- ---- 486: not into a record with neither ---------------------------------
 -- The duplicate holds the only affiliate record, and the record kept has
 -- neither a portal login nor an affiliate record: the preview names it, the
 -- merge refuses with the preview's words, and nothing changes.
 declare s0 text; s1 text; p jsonb; e text; begin
  s0:=pg_temp.mrg_state(keep,dup);
  p:=preview_customer_merge(keep,dup);
  begin
   perform merge_customer_records(keep,dup,'the other way round',gen_random_uuid());
   -- reached only when the call returns: what it left, before it is undone
   s1:=pg_temp.mrg_state(keep,dup);
   raise exception 'the merge went through (undone)';
  exception when others then e:=sqlerrm; end;
  s1:=coalesce(s1,pg_temp.mrg_state(keep,dup));
  if (p->>'can_merge')::boolean is false
     and jsonb_array_length(p->'blocking')=1
     and p->'blocking'->0->>'issue'='duplicate_has_affiliate_account'
     and e='This merge needs review first: '||(p->'blocking'->0->>'detail')
     and s1=s0 then
   raise notice 'PASS: 486: a duplicate that holds the affiliate record is not merged into a record with neither a portal login nor an affiliate record: the preview lists duplicate_has_affiliate_account alone, the merge refuses with its words, and nothing changes';
  else
   v486:=coalesce(e,'?')||' / blocking '||coalesce(p->>'blocking','?')
         ||case when s1=s0 then '' else ' / something changed' end;
   raise notice 'FAIL: 486: a duplicate that holds the affiliate record is not merged into a record with neither a portal login nor an affiliate record: %', v486;
  end if;
 end;
 -- the record kept is given a portal login (no affiliate record of its own;
 -- a shape only this test makes, see the header), so the merge may carry the
 -- duplicate's affiliate record across to it
 declare u uuid:=gen_random_uuid(); begin
  insert into auth.users(id,email,email_confirmed_at) values(u,'mrg-keep-login@example.invalid',now());
  -- triggers off for this insert only: the welcome WhatsApp's, and the
  -- foreign-key checks (the row meets its keys)
  set local session_replication_role = replica;
  insert into affiliate_accounts(auth_user_id,customer_id,status) values(u,keep,'claimed');
  set local session_replication_role = origin;
 end;

 -- ---- a commission between the two must stop it ---------------------------
 insert into commissions(invoice_id,buyer_customer_id,referrer_customer_id,tier,product_type,
                         line_amount,rate,commission_amount,status)
  values(inv,keep,dup,'tier1','own',100,15,15,'earned');
 if (preview_customer_merge(keep,dup)->>'can_merge')::boolean then
  raise exception 'A commission between the two did not block the merge'; end if;
 delete from commissions where buyer_customer_id=keep and referrer_customer_id=dup;

 -- ---- the merge -----------------------------------------------------------
 r:=merge_customer_records(keep,dup,'same person, duplicate record',rq);
 if not (r->>'success')::boolean then raise exception 'The merge did not report success'; end if;

 -- everything moved
 if (select customer_id from invoices where id=inv)<>keep then raise exception 'The invoice did not move'; end if;
 -- credit is drawn down and reissued, never repointed
 if (select remaining_amount from customer_credit_lots where id=lot)<>0 then
  raise exception 'The duplicate''s lot was not drawn down'; end if;
 if (select customer_id from customer_credit_lots where id=lot)<>dup then
  raise exception 'The original lot was repointed instead of reissued'; end if;
 -- 445: the replacement keeps the lot's own source and names the lot it
 -- replaces (reassigned_from_lot_id); before 445 it was 'customer_merge'.
 if (select coalesce(sum(remaining_amount),0) from customer_credit_lots
      where customer_id=keep and (source_type='customer_merge' or reassigned_from_lot_id=lot))<>300 then
  raise exception 'The replacement credit is wrong'; end if;
 if (select count(*) from customer_reward_vouchers where customer_id=dup)<>0 then
  raise exception 'A voucher stayed with the duplicate'; end if;
 if (select referred_by from customers where id=other)<>keep then
  raise exception 'The referred customer still points at the duplicate'; end if;

 -- the balance was carried into the surviving wallet, and the append-only
 -- ledger was left recording what actually happened at the time
 if (select count(*) from customer_credit_ledger where customer_id=dup)=0 then
  raise exception 'The historical ledger entries were rewritten'; end if;
 if (select wallet_id from customer_credit_lots
       where customer_id=keep and (source_type='customer_merge' or reassigned_from_lot_id=lot))<>keep_wallet then
  raise exception 'The replacement is not in the surviving wallet'; end if;
 if (select coalesce(sum(remaining_amount),0) from customer_credit_lots
      where customer_id=keep and status='active')<>400 then
  raise exception 'The combined balance is wrong'; end if;

 -- the duplicate's affiliate record came across: the keeper now holds that
 -- record and the duplicate holds none
 if exists (select 1 from customer_affiliates where customer_id=dup)
    or (select id from customer_affiliates where customer_id=keep) is distinct from dup_aff then
  raise exception 'The affiliate record did not move'; end if;

 -- the duplicate is retired, not destroyed
 if (select deleted_at from customers where id=dup) is null then
  raise exception 'The duplicate was not retired'; end if;
 if (select count(*) from customers where id=dup)<>1 then
  raise exception 'The duplicate row was destroyed'; end if;
 if (select notes from customers where id=dup) not like '%Merged into%' then
  raise exception 'The duplicate does not record where it went'; end if;

 -- ---- a retry does not merge twice ----------------------------------------
 r:=merge_customer_records(keep,dup,'same person, duplicate record',rq);
 if not (r->>'replayed')::boolean then raise exception 'A retry was not recognised'; end if;

 raise notice 'PASS: a duplicate hands over its invoices, credit, vouchers, affiliate record and referrals, balances are carried into one wallet, the record is retired rather than destroyed, retries do not repeat it, and two affiliate records or a commission between the pair stop it for review';
 if v486 is not null then
  raise exception 'FAIL: 486: a duplicate that holds the affiliate record is not merged into a record with neither a portal login nor an affiliate record: %', v486; end if;
end $$;
rollback;
