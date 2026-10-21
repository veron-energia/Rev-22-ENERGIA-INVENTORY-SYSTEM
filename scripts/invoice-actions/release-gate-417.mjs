// Release gate for supabase/417_refund_cancel_requests_and_rental_returns.sql.
//
// 417 drops delete_invoice(uuid) and keeps only delete_invoice(uuid, text),
// which refuses an empty reason (the Owner, 9 Oct 2026, Q4: staff give a
// short reason, kept in the history). A page that still calls
// delete_invoice with no p_reason is answered "Give a short reason for
// deleting this invoice", and staff have no way to give one.
//
// So 417 goes to production only in the same release as the invoice page's
// delete reason (batch B16, src/pages/InvoicesPage.tsx). Run this from the
// repository's root on the code to be released, before applying 417:
//   node scripts/invoice-actions/release-gate-417.mjs
// It prints PASS when every call to delete_invoice in src/ and
// supabase/functions/ sends p_reason, and fails (exit 1) naming each call
// that does not. While it fails, hold 417 back.
//
// It is not one of the *.test.mjs page tests: it fails on purpose until the
// page change is in.
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join, relative } from 'node:path';

const roots = ['src', 'supabase/functions'];
const exts = /\.(ts|tsx|js|jsx|mjs)$/;

function* files(dir) {
  let names;
  try { names = readdirSync(dir); } catch { return; }
  for (const name of names) {
    if (name === 'node_modules' || name.startsWith('.')) continue;
    const p = join(dir, name);
    const s = statSync(p);
    if (s.isDirectory()) yield* files(p);
    else if (exts.test(name)) yield p;
  }
}

// The text of the call from "rpc(" to its closing bracket.
function callText(text, start) {
  let depth = 0;
  for (let i = start; i < text.length; i++) {
    const ch = text[i];
    if (ch === '(') depth++;
    else if (ch === ')') { depth--; if (depth === 0) return text.slice(start, i + 1); }
  }
  return text.slice(start);
}

const calls = [];
const bad = [];
for (const root of roots) {
  for (const file of files(root)) {
    const text = readFileSync(file, 'utf8');
    const re = /rpc\s*(<[^>]*>)?\s*\(\s*['"`]delete_invoice['"`]/g;
    let m;
    while ((m = re.exec(text))) {
      const open = text.indexOf('(', m.index + 3);
      const call = callText(text, open);
      const line = text.slice(0, m.index).split('\n').length;
      const where = `${relative('.', file)}:${line}`;
      calls.push(where);
      if (!/\bp_reason\s*:/.test(call)) bad.push(where);
    }
  }
}

if (bad.length) {
  console.error(`FAIL: delete_invoice is called without p_reason at ${bad.join(', ')}.`);
  console.error('417 refuses a delete with no reason. Ship the page\'s delete reason (B16) with 417, or hold 417 back.');
  process.exit(1);
}
console.log(`PASS: every call to delete_invoice sends p_reason (${calls.length} found${calls.length ? ': ' + calls.join(', ') : ''}).`);
