// Generate a reviewable SQL artifact; never connects to a database.
import { readFileSync, writeFileSync } from 'node:fs';
import { isValidE164 } from '../../src/lib/customer-phones/normalize.mjs';
const [input, output, ownerId] = process.argv.slice(2);
if (!input || !output || !/^[0-9a-f-]{36}$/i.test(ownerId ?? '')) throw new Error('Usage: node scripts/customer-phones/plan-sql.mjs reviewed-plan.json apply-reviewed-plan.sql owner-profile-uuid');
const rows=JSON.parse(readFileSync(input,'utf8'));
if (!Array.isArray(rows) || rows.some(r=>!isValidE164(r.normalized_phone) || !r.reason?.trim())) throw new Error('Reviewed plan requires valid E.164 numbers and reasons.');
const json=JSON.stringify(rows).replaceAll("'","''");
writeFileSync(output, `-- REVIEW THIS PLAN BEFORE EXECUTION. All rows commit together or none do.\nbegin;\nset local standard_conforming_strings=on;\nselect set_config('request.jwt.claim.sub','${ownerId}',true);\nselect public.apply_customer_phone_review('${json}'::jsonb);\ncommit;\n`);
console.log(`Prepared SQL for ${rows.length} reviewed changes. Nothing was applied.`);
