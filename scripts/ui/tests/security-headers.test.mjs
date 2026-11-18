// The browser security headers every page of the app is sent with (security
// audit of 17 Nov 2026, finding L8; the user, 18 Nov 2026, in two steps).
//
// Vercel sends what vercel.json's "headers" say, for every path: the app may
// not be shown in a frame by any site (frame-ancestors, and X-Frame-Options for
// older browsers), a file is taken as the type it is sent as (nosniff), a link
// to another site carries only the app's origin (Referrer-Policy), and (step 2)
// a Content-Security-Policy lets only the app's own script files run. HSTS is
// Vercel's own (max-age=63072000; includeSubDomains; preload) and not set here.
//
// The policy holds only while no page writes an inline <script>: the print
// windows (window.open(''), which inherit the app's policy) are laid out from
// the app by printWhenReady (src/lib/printWindow.ts), not by a script of their own.
// Nor may HTML the app writes carry an inline handler (on...="...") or a
// javascript: link. jsPDF's output('pdfobjectnewwindow' | 'pdfjsnewwindow' |
// 'dataurlnewwindow') load a script from cdnjs and build frames: under this
// policy they fail, so the app keeps to save(), output('blob') and
// output('datauristring'). The policy has no report address: a violation shows
// only in the browser's console.
//
//   node --test scripts/ui/tests/security-headers.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join } from 'node:path';

const root = new URL('../../../', import.meta.url).pathname;
const config = JSON.parse(readFileSync(root + 'vercel.json', 'utf8'));
const SUPABASE = 'jknfhpgryywsrzdstqzy.supabase.co';

const forEveryPath = () => {
  const blocks = (config.headers ?? []).filter(h => h.source === '/(.*)');
  assert.equal(blocks.length, 1, 'one headers block for every path');
  return Object.fromEntries(blocks[0].headers.map(h => [h.key.toLowerCase(), h.value]));
};
const policy = () => Object.fromEntries(forEveryPath()['content-security-policy'].split(';')
  .map(d => d.trim()).filter(Boolean).map(d => { const [k, ...v] = d.split(/\s+/); return [k, v]; }));

test('every page is sent the four headers', () => {
  const h = forEveryPath();
  assert.deepEqual(Object.keys(h).sort(), ['content-security-policy', 'referrer-policy', 'x-content-type-options', 'x-frame-options']);
  assert.equal(h['x-frame-options'], 'DENY');
  assert.equal(h['x-content-type-options'], 'nosniff');
  assert.equal(h['referrer-policy'], 'strict-origin-when-cross-origin');
});

test('the policy, directive by directive', () => {
  assert.deepEqual(policy(), {
    'default-src': ["'self'"],
    'script-src': ["'self'"],
    'style-src': ["'self'", "'unsafe-inline'", 'https://fonts.googleapis.com'],
    'font-src': ["'self'", 'https://fonts.gstatic.com'],
    'img-src': ["'self'", 'data:', 'blob:', 'https://energia.sg', `https://${SUPABASE}`],
    'connect-src': ["'self'", `https://${SUPABASE}`, `wss://${SUPABASE}`],
    'worker-src': ["'self'", 'blob:'],
    'object-src': ["'none'"],
    'base-uri': ["'self'"],
    'form-action': ["'self'"],
    'frame-ancestors': ["'none'"],
  });
});

test('scripts: the app\'s own files only (no inline, no eval, no other host)', () => {
  const s = policy()['script-src'];
  assert.deepEqual(s, ["'self'"]);
  for (const bad of ["'unsafe-inline'", "'unsafe-eval'", '*', 'https:', 'data:', 'blob:']) assert.ok(!s.includes(bad), bad);
});

test('no source file writes an inline <script> (a print window would be stopped)', () => {
  const hits = [];
  const walk = d => { for (const n of readdirSync(d)) { const p = join(d, n); if (statSync(p).isDirectory()) walk(p);
    else if (/\.(ts|tsx|mjs|js)$/.test(n)) readFileSync(p, 'utf8').split('\n').forEach((l, i) => {
      if (/<script/i.test(l) && !/^\s*(\/\/|\*|\/\*)/.test(l)) hits.push(`${p.slice(root.length)}:${i + 1}`); }); } };
  walk(root + 'src');
  assert.deepEqual(hits, []);
});

test('no inline handler (on...="...") or javascript: link in the HTML the app writes, and no jsPDF window output', () => {
  const hits = [];
  const walk = d => { for (const n of readdirSync(d)) { const p = join(d, n); if (statSync(p).isDirectory()) walk(p);
    else if (/\.(ts|tsx|mjs|js)$/.test(n)) readFileSync(p, 'utf8').split('\n').forEach((l, i) => {
      if (/^\s*(\/\/|\*|\/\*)/.test(l)) return;
      if (/\son[a-z]+\s*=\s*["']/i.test(l) || /javascript:/i.test(l) || /(pdfobject|pdfjs|dataurl)newwindow/i.test(l)) hits.push(`${p.slice(root.length)}:${i + 1}`); }); } };
  walk(root + 'src');
  assert.deepEqual(hits, []);
});

test('the single-page rewrite is unchanged, and no header block is narrower than every path', () => {
  assert.deepEqual(config.rewrites, [{ source: '/((?!assets/).*)', destination: '/index.html' }]);
  assert.ok((config.headers ?? []).every(h => h.source === '/(.*)'));
});
