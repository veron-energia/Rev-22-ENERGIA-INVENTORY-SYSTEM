// Run only against the explicitly named disposable local database. Does not
// create/drop a database. Bootstrap + migrations must already be installed.
import { execFile, execFileSync } from 'node:child_process';
import { promisify } from 'node:util';
import assert from 'node:assert/strict';
import { inspectPhone } from '../../../src/lib/customer-phones/normalize.mjs';
const run = promisify(execFile);
if (process.env.PGDATABASE !== 'energia_phone_test' || !process.env.PGHOST?.startsWith('/tmp/energia-')) {
  throw new Error('Set PGDATABASE=energia_phone_test and PGHOST to the isolated /tmp/energia-* socket directory. Remote databases are refused.');
}
const args = ['-X','-q','-A','-t','-v','ON_ERROR_STOP=1'];
const sql = statement => execFileSync('psql',[...args,'-c',statement],{encoding:'utf8'}).trim();
const owner = "select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',true);";
console.log(execFileSync('psql',[...args,'-f','supabase/tests/phase77_customer_phone_policy_tests.sql'],{encoding:'utf8'}));
const inputs=['91234567','6591234567','+65 9123 4567','(+65) 9123-4567','006591234567','0123456789','123456789','60123456789','93234567','62345678','12345678','+60123456789','+447911123456','+12025550123','AFF-123','++6591234567','+65091234567','+6591234567 ext 9',''];
for (const input of inputs) for(const hint of [null,'SG','MY']) {
  const result = JSON.parse(sql(`select public.inspect_customer_phone('${input.replaceAll("'","''")}',${hint ? `'${hint}'`:'null'});`));
  assert.deepEqual(result,inspectPhone(input,hint),`${input}/${hint}`);
}
console.log(`PASS: SQL/JS normalization parity (${inputs.length * 3} cases).`);
// New public RPCs and private helper/table access must remain restricted.
assert.equal(sql("select has_function_privilege('anon','public.customer_phone_name_matches(text,text)','execute');"),'f');
assert.equal(sql("select has_table_privilege('authenticated','public.customer_phone_capacity','update');"),'f');
// Simultaneous transactions all start while earlier ones still hold row locks.
const token = Date.now().toString();
const phone = '+6591237790';
assert.equal(sql(`select count(*) from public.customers where phone='${phone}';`),'0','concurrency test phone must be unused');
try {
  const results = await Promise.allSettled(Array.from({length:8},(_,i)=>run('psql',[...args,'-c',`begin; insert into public.customers(full_name,phone) values('Concurrency ${token} ${i}','${phone}'); select pg_sleep(0.15); commit;`])));
  assert.equal(results.filter(r=>r.status==='fulfilled').length,3,'exactly three concurrent requests should succeed');
  for(const r of results.filter(r=>r.status==='rejected')) assert.match(r.reason.stderr,/CUSTOMER_PHONE_LIMIT/);
  assert.equal(sql(`select count(*) from public.customers where phone='${phone}';`),'3');
  assert.equal(sql(`select used from public.customer_phone_capacity where phone='${phone}';`),'3');
  console.log('PASS: 8 simultaneous requests, 3 committed, 5 rejected; counter matches customer rows.');
} finally {
  sql(`delete from public.customers where full_name like 'Concurrency ${token} %';`);
}
// Same identity, concurrent public survey submissions: one customer, one survey.
const identityPhone='+6591237791';
sql(`insert into public.stores(name,code) values('Concurrent Survey','CS-${token}');
insert into public.customer_source_options(label) values('CS-${token}');
insert into public.survey_links(token,store_id) select 'CS-${token}',id from public.stores where code='CS-${token}';`);
try {
  const statement=`select public.submit_health_survey('CS-${token}',jsonb_build_object('full_name','Concurrent Identity ${token}','phone','${identityPhone}','email','concurrent@test.invalid','signature_data','sig','source_option_id',(select id from public.customer_source_options where label='CS-${token}')),null,null);`;
  const results=await Promise.allSettled([run('psql',[...args,'-c',statement]),run('psql',[...args,'-c',statement])]);
  assert.equal(results.filter(r=>r.status==='fulfilled').length,1);
  const rejected=results.find(r=>r.status==='rejected'); assert.match(rejected.reason.stderr,/HEALTH_SURVEY_ALREADY_EXISTS/);
  assert.equal(sql(`select count(*) from public.customers where phone='${identityPhone}';`),'1');
  console.log('PASS: simultaneous identical survey submissions create only one customer and one survey.');
} finally {
  sql(`delete from public.health_surveys where full_name='Concurrent Identity ${token}';
  delete from public.customers where full_name='Concurrent Identity ${token}';
  delete from public.survey_links where token='CS-${token}';
  delete from public.customer_source_options where label='CS-${token}';
  delete from public.stores where code='CS-${token}';`);
}
