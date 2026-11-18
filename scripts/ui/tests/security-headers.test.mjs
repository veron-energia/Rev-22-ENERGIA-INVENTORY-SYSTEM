// The browser security headers every page of the app is sent with (security
// audit of 17 Nov 2026, finding L8; the user, 18 Nov 2026, step 1 of two).
//
// Vercel sends what vercel.json's "headers" say, for every path: the app may
// not be shown in a frame by any site (frame-ancestors, and X-Frame-Options for
// older browsers), a file is taken as the type it is sent as (nosniff), and a
// link to another site carries only the app's origin (Referrer-Policy). HSTS is
// Vercel's own (max-age=63072000; includeSubDomains; preload) and not set here.
// Step 2 (a full Content-Security-Policy) waits for printing to need no inline
// script: this test fails if a script policy is added before that.
//
//   node --test scripts/ui/tests/security-headers.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const config = JSON.parse(readFileSync(new URL('../../../vercel.json', import.meta.url), 'utf8'));

const forEveryPath = () => {
  const blocks = (config.headers ?? []).filter(h => h.source === '/(.*)');
  assert.equal(blocks.length, 1, 'one headers block for every path');
  return Object.fromEntries(blocks[0].headers.map(h => [h.key.toLowerCase(), h.value]));
};

test('every page is sent the four headers, exactly', () => {
  assert.deepEqual(forEveryPath(), {
    'content-security-policy': "frame-ancestors 'none'",
    'x-frame-options': 'DENY',
    'x-content-type-options': 'nosniff',
    'referrer-policy': 'strict-origin-when-cross-origin',
  });
});

test('the Content-Security-Policy is frame-ancestors alone until printing needs no inline script', () => {
  const csp = forEveryPath()['content-security-policy'];
  assert.doesNotMatch(csp, /script-src|default-src/,
    'a script policy would stop the print windows, which run an inline script (step 2)');
});

test('the single-page rewrite is unchanged', () => {
  assert.deepEqual(config.rewrites, [{ source: '/((?!assets/).*)', destination: '/index.html' }]);
});

test('no header block is narrower than every path (so none is missed on a route)', () => {
  assert.ok((config.headers ?? []).every(h => h.source === '/(.*)'));
});
