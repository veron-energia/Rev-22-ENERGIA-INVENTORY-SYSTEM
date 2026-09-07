import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { resolve } from 'node:path';
import { createHash } from 'node:crypto';
import Papa from 'papaparse';
import { inspectPhone } from '../../src/lib/customer-phones/normalize.mjs';

export function buildReport(customers) {
  const ids = new Set();
  const rows = customers.map(c => {
    if (!c.id || ids.has(c.id) || !Object.hasOwn(c, 'deleted_at') || typeof c.phone !== 'string') {
      throw new Error('Export must contain distinct id, full_name, phone (as text), and deleted_at for every customer, including deleted/inactive rows.');
    }
    ids.add(c.id);
    // Nationality, citizenship and store location are never phone-country evidence.
    const hint = ['customer_confirmed', 'verified_phone_country'].includes(c.phone_country_source) ? c.phone_country : null;
    const inspection = inspectPhone(c.phone, hint);
    return { customer_id: c.id, full_name: c.full_name, original_phone: c.phone, deleted_at: c.deleted_at || null,
      is_active: c.is_active, phone_country_evidence: hint ? c.phone_country_source : null, ...inspection };
  });
  const groups = new Map();
  for (const row of rows) if (!row.deleted_at && row.normalized) {
    if (!groups.has(row.normalized)) groups.set(row.normalized, []);
    groups.get(row.normalized).push(row);
  }
  const conflicts = [...groups].filter(([, v]) => v.length > 3).map(([phone, records]) => ({ phone, count: records.length, customer_ids: records.map(r => r.customer_id) }));
  for (const row of rows) {
    row.non_deleted_count = row.normalized ? (groups.get(row.normalized)?.length ?? 0) : null;
    if (!row.deleted_at && row.non_deleted_count > 3) {
      row.status = 'pending_review';
      row.reason += ' More than 3 non-deleted customers normalize to this number; resolve the group manually.';
    }
    row.suggested_numbers = row.candidates;
    row.suggested_countries = row.candidates.map(n => n.startsWith('+65') ? 'SG' : n.startsWith('+60') ? 'MY' : 'explicit international');
  }
  const ready = rows.filter(r => r.status === 'ready' && r.original_phone !== r.normalized);
  return {
    generated_at: new Date().toISOString(), mode: 'DRY RUN — no database connection or writes',
    input_sha256: createHash('sha256').update(JSON.stringify(customers)).digest('hex'),
    summary: { total: rows.length, non_deleted: rows.filter(r => !r.deleted_at).length, proposed_changes: ready.length,
      pending_review: rows.filter(r => r.status === 'pending_review').length, over_capacity_groups: conflicts.length },
    conflicts, rows,
    proposed_plan: ready.map(r => ({ customer_id: r.customer_id, original_phone: r.original_phone, normalized_phone: r.normalized, reason: `Reviewed normalization: ${r.reason}` })),
  };
}
export function markdownReport(report) {
  const esc = s => String(s ?? '').replaceAll('|', '\\|').replace(/[\r\n]+/g, ' ');
  return `# Customer phone dry run\n\n${report.mode}\n\nInput SHA-256: \`${report.input_sha256}\`\n\n` +
    Object.entries(report.summary).map(([k,v]) => `- ${k}: ${v}`).join('\n') +
    '\n\n## Pending manual review\n\n| Customer ID | Name | Original phone | Suggested countries/numbers | Reason |\n|---|---|---|---|---|\n' +
    report.rows.filter(r=>r.status==='pending_review').map(r=>`| ${[r.customer_id,r.full_name,r.original_phone,r.suggested_countries.map((c,i)=>`${c}: ${r.suggested_numbers[i]}`).join('; '),r.reason].map(esc).join(' | ')} |`).join('\n') +
    '\n\nThe proposed plan excludes uncertain numbers and non-deleted records in over-capacity groups. Review it before applying; names, IDs, invoices, referrals and survey links are never merged or reassigned. Original values are included in this report and the database migration mapping.\n';
}
if (process.argv[1] && resolve(process.argv[1]) === resolve(new URL(import.meta.url).pathname)) {
  const [input, output] = process.argv.slice(2);
  if (!input || !output) throw new Error('Usage: node scripts/customer-phones/report.mjs customers.json|csv output-directory');
  const content = readFileSync(input, 'utf8');
  let rows;
  if (input.endsWith('.csv')) {
    const parsed = Papa.parse(content, { header: true, skipEmptyLines: true, dynamicTyping: false });
    if (parsed.errors.length) throw new Error(JSON.stringify(parsed.errors));
    rows = parsed.data;
  } else rows = JSON.parse(content);
  if (!Array.isArray(rows)) throw new Error('Input must be a complete customer array.');
  const report = buildReport(rows);
  mkdirSync(output, { recursive: true });
  writeFileSync(resolve(output, 'report.json'), JSON.stringify(report,null,2)+'\n');
  writeFileSync(resolve(output, 'review.csv'), Papa.unparse(report.rows.map(r => ({
    customer_id:r.customer_id,full_name:r.full_name,original_phone:r.original_phone,deleted_at:r.deleted_at,
    suggested_country:r.suggested_countries.join('; '),normalized_phone:r.normalized,
    suggested_numbers:r.suggested_numbers.join('; '),non_deleted_count:r.non_deleted_count,status:r.status,reason:r.reason,
  })), { escapeFormulae: true })+'\n');
  writeFileSync(resolve(output, 'proposed-plan.json'), JSON.stringify(report.proposed_plan,null,2)+'\n');
  writeFileSync(resolve(output, 'report.md'), markdownReport(report));
  console.log(JSON.stringify(report.summary));
}
