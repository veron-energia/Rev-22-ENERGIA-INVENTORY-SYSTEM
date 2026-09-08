// Nothing server-side may reach the browser.
//
// Scans the frontend source, and the built bundle when one is present. A secret
// that leaks into a Vite build is public the moment the site deploys, so this is
// checked mechanically rather than by remembering.

import test from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync, statSync, existsSync } from 'node:fs';
import { join } from 'node:path';

const root = new URL('../../../', import.meta.url).pathname;

function filesUnder(dir, match) {
  const out = [];
  const walk = (d) => {
    for (const entry of readdirSync(d)) {
      const full = join(d, entry);
      if (statSync(full).isDirectory()) walk(full);
      else if (match.test(entry)) out.push(full);
    }
  };
  if (existsSync(dir)) walk(dir);
  return out;
}

const sources = filesUnder(join(root, 'src'), /\.(ts|tsx|mjs|d\.mts)$/);

test('the frontend never names a server-only secret', () => {
  const forbidden = [
    'SERVICE_ROLE_KEY', 'SUPABASE_SECRET_KEY',
    'PABBLY_AUTH_EMAIL_WEBHOOK_URL', 'PABBLY_AUTH_EMAIL_SHARED_SECRET',
    'AUTH_EMAIL_RATE_LIMIT_HASH_SECRET', 'delivery_secret',
  ];
  for (const file of sources) {
    const text = readFileSync(file, 'utf8');
    for (const name of forbidden) {
      assert.ok(!text.includes(name), `${file.replace(root, '')} mentions ${name}`);
    }
  }
});

test('the frontend never calls the Auth admin API', () => {
  // admin.generateLink needs the service-role key. A browser that called it
  // either cannot work or is holding a key it must never hold.
  for (const file of sources) {
    const text = readFileSync(file, 'utf8');
    assert.ok(!text.includes('auth.admin'), `${file.replace(root, '')} calls auth.admin`);
    assert.ok(!text.includes('generateLink'), `${file.replace(root, '')} calls generateLink`);
  }
});

test('no VITE_ variable carries anything server-side', () => {
  // Vite inlines every VITE_-prefixed value into the bundle, so a VITE_ name is
  // a promise that the value is public. Checked by shape rather than by an exact
  // allowlist, so unrelated work can add its own public variables freely.
  const used = new Set();
  for (const file of sources) {
    for (const match of readFileSync(file, 'utf8').matchAll(/VITE_[A-Z0-9_]+/g)) used.add(match[0]);
  }
  assert.ok(used.has('VITE_SUPABASE_URL') && used.has('VITE_SUPABASE_ANON_KEY'), 'expected the existing public pair');

  for (const name of used) {
    assert.doesNotMatch(name, /SECRET|SERVICE_ROLE|PASSWORD|WEBHOOK|PABBLY|PRIVATE|HASH/, `${name} must not be a VITE_ variable`);
  }
  // And none of this work's server-side names may ever appear with a VITE_ prefix.
  for (const name of [
    'SUPABASE_SERVICE_ROLE_KEY', 'PABBLY_AUTH_EMAIL_WEBHOOK_URL', 'PABBLY_AUTH_EMAIL_SHARED_SECRET',
    'AUTH_EMAIL_FROM_ADDRESS', 'AUTH_EMAIL_RATE_LIMIT_HASH_SECRET',
  ]) {
    assert.ok(!used.has(`VITE_${name}`), `VITE_${name} must never exist`);
  }
});

test('no Auth email-triggering call is left in the frontend', () => {
  // These would go out through Supabase's own sender, which is the path this
  // work replaced. signInWithPassword is fine: it sends no email.
  const replaced = ['resetPasswordForEmail', 'inviteUserByEmail', 'signInWithOtp'];
  for (const file of sources) {
    const text = readFileSync(file, 'utf8');
    for (const call of replaced) {
      assert.ok(!text.includes(call), `${file.replace(root, '')} still calls ${call}`);
    }
    // supabase.auth.signUp and auth.updateUser({password}) both trigger or
    // accompany Auth email; both now go through the Edge Functions.
    assert.ok(!/supabase\.auth\.signUp\b/.test(text), `${file.replace(root, '')} still calls auth.signUp`);
    assert.ok(!/auth\.updateUser\(\s*\{\s*password/.test(text), `${file.replace(root, '')} still calls auth.updateUser({password})`);
  }
});

test('a built bundle carries no secret and no webhook host', { skip: !existsSync(join(root, 'dist')) }, () => {
  const assets = filesUnder(join(root, 'dist'), /\.(js|css|html)$/);
  assert.ok(assets.length > 0, 'expected built assets');
  for (const file of assets) {
    const text = readFileSync(file, 'utf8');
    for (const needle of [
      'SERVICE_ROLE', 'service_role', 'delivery_secret',
      'PABBLY_AUTH_EMAIL', 'connect.pabbly.com', 'AUTH_EMAIL_RATE_LIMIT_HASH_SECRET',
      'sb_secret_',
    ]) {
      assert.ok(!text.includes(needle), `${file.replace(root, '')} contains ${needle}`);
    }
  }
});
