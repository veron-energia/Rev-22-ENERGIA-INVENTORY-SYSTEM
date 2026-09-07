import { readFileSync, writeFileSync } from 'node:fs';
const output = process.argv[2];
if (!output) throw new Error('Usage: node scripts/customer-phones/bundle-migration.mjs output.sql');
const files=['161_customer_phone_policy.sql','162_customer_phone_identity_flows.sql','163_customer_phone_review_tools.sql'];
writeFileSync(output,'-- Atomic phone-policy deployment. No legacy phone cleanup.\nbegin;\n'+files.map(f=>readFileSync('supabase/'+f,'utf8').replace(/^begin;\s*$/m,'').replace(/^commit;\s*$/m,'')).join('\n')+'\ncommit;\n');
console.log('Prepared a single-transaction deployment bundle. Nothing was applied.');
