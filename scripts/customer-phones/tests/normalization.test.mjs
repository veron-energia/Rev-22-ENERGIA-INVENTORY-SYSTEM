import test from 'node:test';
import { createRequire } from 'node:module';
import { readFileSync } from 'node:fs';
import rules from '../../../src/lib/customer-phones/rules.json' with { type: 'json' };
import assert from 'node:assert/strict';
import { parsePhoneNumberFromString } from 'libphonenumber-js/max';
import { inspectPhone, isValidE164, normalizeName, matchCustomers } from '../../../src/lib/customer-phones/normalize.mjs';
import { buildReport } from '../report.mjs';

test('SG equivalents, explicit MY and domestic MY normalize without changing explicit codes', () => {
  for (const raw of ['91234567','6591234567','+65 9123 4567','(+65) 9123-4567','006591234567']) assert.equal(inspectPhone(raw).normalized,'+6591234567');
  for (const raw of ['0123456789','60123456789','+60123456789']) assert.equal(inspectPhone(raw).normalized,'+60123456789');
  assert.equal(inspectPhone('+447911123456','SG').normalized,'+447911123456');
  assert.equal(inspectPhone('123456789','MY').normalized,'+60123456789');
});
test('uncertain numbers remain pending; explicit country codes are not repaired by guessing', () => {
  for (const raw of ['93234567','123456789','12345678','123','AFF-123','+6512345678','++6591234567','+65091234567','91234567 ext 5']) assert.equal(inspectPhone(raw).normalized,null,raw);
  assert.deepEqual(inspectPhone('93234567').candidates,['+6593234567','+6093234567']);
  assert.equal(inspectPhone('93234567','MY').normalized,'+6093234567');
  assert.equal(inspectPhone('93234567','SG').normalized,'+6593234567');
});
test('generated E.164 validation agrees with the parsing library', () => {
  for (const number of ['+6591234567','+6581234567','+6562345678','+6512345678','+60123456789','+6093234567','+447911123456','+12025550123','+81312345678','+8613812345678','+9991234567']) {
    assert.equal(isValidE164(number),parsePhoneNumberFromString(number)?.isValid() ?? false,number);
  }
});
test('exact phone plus normalized name, never first/fuzzy/history/deleted', () => {
  const rows=[{id:'a',full_name:' Ann  TAN ',phone:'91234567'}, {id:'b',full_name:'Bob Tan',phone:'+6591234567'}, {id:'deleted',full_name:'Ann Tan',phone:'+6591234567',deleted_at:'2026-01-01'}];
  assert.equal(normalizeName(' Ann  TAN '),'ann tan');
  assert.equal(matchCustomers(rows,'6591234567','ann tan').matches[0].id,'a');
  assert.equal(matchCustomers(rows,'6591234567','an tan').status,'new');
  assert.equal(matchCustomers([...rows,{id:'c',full_name:'ann tan',phone:'+6591234567'}],'91234567','Ann Tan').status,'ambiguous');
});
test('dry run reports conflicts, ignores deleted capacity and nationality, retains originals', () => {
  const rows=['91234567','6591234567','+65 9123 4567','+6591234567'].map((phone,i)=>({id:String(i),full_name:`Customer ${i}`,phone,deleted_at:null,is_active:i!==2}));
  rows.push({id:'deleted',full_name:'Deleted',phone:'+6591234567',deleted_at:'2026-01-01'});
  rows.push({id:'ambiguous',full_name:'Ambiguous',phone:'93234567',deleted_at:null,nationality:'Singaporean'});
  rows.push({id:'confirmed',full_name:'Confirmed',phone:'123456789',deleted_at:null,phone_country:'MY',phone_country_source:'customer_confirmed'});
  const report=buildReport(rows);
  assert.equal(report.conflicts[0].count,4);
  assert.equal(report.summary.pending_review,5);
  assert.equal(report.proposed_plan.length,1);
  assert.equal(report.proposed_plan[0].normalized_phone,'+60123456789');
  assert.equal(report.rows.find(r=>r.customer_id==='ambiguous').normalized,null);
  assert.equal(report.rows[0].original_phone,'91234567');
});

test('database and application use the pinned metadata snapshot', () => {
  const require=createRequire(import.meta.url);
  assert.equal(rules.version,require('libphonenumber-js/package.json').version);
  const sql=readFileSync('supabase/161_customer_phone_policy.sql','utf8');
  const embedded=sql.match(/\$json\$([\s\S]*?)\$json\$/)[1];
  assert.deepEqual(JSON.parse(embedded),rules.rules);
});
