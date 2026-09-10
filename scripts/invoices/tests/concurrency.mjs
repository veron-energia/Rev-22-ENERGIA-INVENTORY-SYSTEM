import { spawn } from 'node:child_process';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { resolve } from 'node:path';
function sql(query) { return new Promise(resolve => {
 const p=spawn('scripts/invoices/local-sql.sh',['-Atq'],{stdio:['pipe','pipe','pipe']});let out='',error='';
 p.stdout.on('data',s=>out+=s);p.stderr.on('data',s=>error+=s);p.on('close',code=>resolve({code,out:out.trim(),error}));p.stdin.end(query);
}); }
const target=await sql('SHOW data_directory;');
assert.equal(target.out,resolve('.invoice-test/data'),'Refusing a database outside the isolated invoice cluster');
const o=randomUUID(), c=randomUUID(), st=randomUUID(), p=randomUUID(), m=randomUUID();
const invoice=randomUUID(), item=randomUUID(), payment=randomUUID();
const setup=await sql(`begin;
insert into auth.users(id,email) values('${o}','concurrency-${o}@tests.invalid');
insert into profiles(id,full_name,email,role) values('${o}','Concurrency Owner','concurrency-${o}@tests.invalid','owner');
select set_config('request.jwt.claim.sub','${o}',true);
insert into stores(id,name,code,country_code) values('${st}','Concurrency Test','CONC','SG');
insert into customers(id,full_name,phone) values('${c}','Concurrency Customer','+6591238881');
insert into products(id,name,sku,product_type) values('${p}','Concurrent Product','C-${p}','own');
insert into store_inventory(store_id,product_id,current_qty) values('${st}','${p}',10);
insert into payment_methods(id,name) values('${m}','Concurrency Cash');
insert into invoices(id,invoice_no,customer_id,store_id,status,subtotal,total_amount,paid_amount,created_by,business_date)
values('${invoice}','CONC-${invoice}','${c}','${st}','paid',100,100,100,'${o}',current_date);
insert into invoice_items(id,invoice_id,product_id,line_kind,quantity,unit_price,line_total) values('${item}','${invoice}','${p}','product',1,100,100);
insert into invoice_payments(id,invoice_id,payment_method_id,amount,received_by) values('${payment}','${invoice}','${m}',100,'${o}');
commit;`);
assert.equal(setup.code,0,setup.error);
const refund=(amount,id)=>`begin;select set_config('request.jwt.claim.sub','${o}',true);
select refund_invoice_recorded('${invoice}','[{"invoice_item_id":"${item}","amount":${amount}}]',
'[{"payment_id":"${payment}","amount":${amount}}]','[]','Concurrent refund','${id}');commit;`;
const results=await Promise.all([sql(refund(80,randomUUID())),sql(refund(80,randomUUID()))]);
assert.equal(results.filter(r=>r.code===0).length,1,JSON.stringify(results));
assert.match(results.find(r=>r.code!==0).error,/remaining discounted line value|net payments|remaining amount/);
const rid=randomUUID();const replays=await Promise.all(Array.from({length:4},()=>sql(refund(20,rid))));
for(const r of replays)assert.equal(r.code,0,r.error);
const check=await sql(`select json_build_object('refunds',count(*),'total',sum(amount),'net',invoice_net_received('${invoice}')) from invoice_refunds where invoice_id='${invoice}';`);
assert.deepEqual(JSON.parse(check.out),{refunds:2,total:100,net:0});
console.log('PASS: concurrent refunds cannot exceed capacity; four concurrent retries return one refund');
const recipient=randomUUID(), packageId=randomUUID();
const benefitSetup=await sql(`begin;select set_config('request.jwt.claim.sub','${o}',true);
insert into customers(id,full_name,phone) values('${recipient}','Corrected Recipient','+6591238882');
insert into credit_packages(id,name,customer_price,paid_credit_amount,allow_product) values('${packageId}','Concurrent benefit',100,120,true);
insert into credit_package_stores(package_id,store_id) values('${packageId}','${st}');
select create_invoice('${st}','${c}',null,'[{"kind":"credit_package","credit_package_id":"${packageId}","quantity":1}]') as inv \\gset
select record_invoice_payment(:'inv','[{"payment_method_id":"${m}","amount":100}]','${randomUUID()}');
select json_build_object('invoice',invoice_id,'benefit',id,'lot',lot_id) from invoice_benefit_values where invoice_id=:'inv';commit;`);
assert.equal(benefitSetup.code,0,benefitSetup.error);
const info=JSON.parse(benefitSetup.out.split('\n').findLast(line=>line.includes('"benefit"')));
const transferIds=[randomUUID(),randomUUID()];
const transfer=id=>`begin;select set_config('request.jwt.claim.sub','${o}',true);
select transfer_invoice_unused_benefit('${info.benefit}','${recipient}','${st}','Concurrent recipient correction','${id}');commit;`;
const transfers=await Promise.all(transferIds.map(id=>sql(transfer(id))));
assert.equal(transfers.filter(r=>r.code===0).length,1,JSON.stringify(transfers));
assert.match(transfers.find(r=>r.code!==0).error,/No unused value remains/);
const winner=transferIds[transfers.findIndex(r=>r.code===0)];
for(const r of await Promise.all(Array.from({length:4},()=>sql(transfer(winner)))))assert.equal(r.code,0,r.error);
const transferCheck=await sql(`select json_build_object('transfers',(select count(*) from invoice_benefit_transfers where invoice_id='${info.invoice}'),
 'remaining',sum(l.remaining_amount),'original',(select remaining_amount from customer_credit_lots where id='${info.lot}'))
 from invoice_benefit_values b join customer_credit_lots l on l.id=b.lot_id where b.invoice_id='${info.invoice}';`);
assert.deepEqual(JSON.parse(transferCheck.out),{transfers:1,remaining:120,original:0});
console.log('PASS: concurrent recipient corrections and four retries move unused value exactly once');
console.log('Fixtures remain only in the disposable test database; rebuild it before another run.');
