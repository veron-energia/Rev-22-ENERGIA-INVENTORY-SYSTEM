// Regenerate only when deliberately updating libphonenumber metadata.
import { createRequire } from 'node:module';
import { readFileSync, writeFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
const require = createRequire(import.meta.url);
const metadata = require('libphonenumber-js/metadata.max.json');
const rules = Object.entries({ ...metadata.countries, ...metadata.nonGeographic }).map(([country, m]) => ({
  country, code: m[0], general: m[2],
  types: m[11].filter(t => t && t[0]).map(t => ({ pattern: t[0], lengths: t[1] || m[3] })),
}));
const data = { version: require('libphonenumber-js/package.json').version, rules };
const json = JSON.stringify(data);
writeFileSync('src/lib/customer-phones/rules.json', json + '\n');
const sqlPath = 'supabase/161_customer_phone_policy.sql';
const sql = readFileSync(sqlPath, 'utf8');
writeFileSync(sqlPath, sql.replace(/-- BEGIN GENERATED PHONE RULES[\s\S]*?-- END GENERATED PHONE RULES/, `-- BEGIN GENERATED PHONE RULES (libphonenumber-js ${data.version}, sha256 ${createHash('sha256').update(json).digest('hex')})
create or replace function public.customer_phone_rules()
returns jsonb language sql immutable parallel safe set search_path = public as $rules$
  select $json$${JSON.stringify(rules)}$json$::jsonb
$rules$;
-- END GENERATED PHONE RULES`));
console.log(`Generated ${rules.length} numbering plans from libphonenumber-js ${data.version}.`);
