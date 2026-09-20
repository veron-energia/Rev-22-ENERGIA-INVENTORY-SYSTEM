// Stored text cannot carry markup into a printed document.
//
// esc() escaped only & and <. It is used inside attributes as well as in text
// — `<img src="${esc(branding.logo_url)}">` — so a stored value containing a
// double quote could close the attribute and open another one. Separately, the
// survey QR print was the only print path that never called esc at all.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { build } from 'esbuild';

const built = await build({
  stdin: { contents: `export { esc } from './src/lib/printDoc';`, resolveDir: process.cwd(), loader: 'ts' },
  bundle: true, write: false, format: 'esm',
  plugins: [{
    name: 'stub-supabase',
    setup(b) {
      b.onResolve({ filter: /(^|\/)supabase$/ }, () => ({ path: 'stub', namespace: 's' }));
      b.onLoad({ filter: /.*/, namespace: 's' }, () => ({ contents: 'export const supabase = {};', loader: 'js' }));
    },
  }],
});
const { esc } = await import('data:text/javascript;base64,' + Buffer.from(built.outputFiles[0].text).toString('base64'));

test('a quote cannot end an attribute and start another', () => {
  const attack = '" onerror="alert(1)';
  const html = `<img src="${esc(attack)}" />`;
  assert.ok(!/onerror=/.test(html.replace(/&quot;/g, '')) || !html.includes('" onerror'),
    'the quote must not survive as a quote');
  assert.ok(esc(attack).includes('&quot;'), 'a double quote is escaped');
  assert.ok(!esc(attack).includes('"'), 'no raw double quote survives');
});

test('a tag cannot be opened or closed by stored text', () => {
  const out = esc('<script>alert(1)</script>');
  assert.ok(!out.includes('<') && !out.includes('>'), 'neither bracket survives');
  assert.equal(out, '&lt;script&gt;alert(1)&lt;/script&gt;');
});

test('single quotes are escaped too, for single-quoted attributes', () => {
  assert.ok(!esc("it's").includes("'"));
});

test('ampersands are escaped once, not twice', () => {
  assert.equal(esc('Tom & Jerry'), 'Tom &amp; Jerry');
  assert.equal(esc('&amp;'), '&amp;amp;', 'an already-escaped entity is escaped again, not left to double-decode');
});

test('ordinary text is unchanged', () => {
  assert.equal(esc('INV-2026-0001'), 'INV-2026-0001');
  assert.equal(esc('Energia Rev 22 (Adelphi)'), 'Energia Rev 22 (Adelphi)');
  assert.equal(esc(null), '');
  assert.equal(esc(undefined), '');
});

test('the survey QR print escapes the store name and the event name', () => {
  // The values are stored, and the event name is typed into a form by staff.
  const src = readFileSync('src/pages/SurveysPage.tsx', 'utf8');
  const qr = src.slice(src.indexOf('const printQr'), src.indexOf('w.document.close()'));
  assert.ok(qr.includes('esc(sName(qrFor.store_id))'), 'the store name is escaped');
  assert.ok(qr.includes('esc(qrFor.event_name)'), 'the event name is escaped');
  assert.ok(!/\$\{sName\(qrFor\.store_id\)\}/.test(qr), 'no unescaped store name remains');
  assert.ok(!/\$\{qrFor\.event_name\}/.test(qr), 'no unescaped event name remains');
});
