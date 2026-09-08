// Configuration loading: which names are required, and what an error may say.

import { assert, assertEquals, assertThrows } from 'jsr:@std/assert@1';
import { loadAllowedOrigins, loadConfig, MissingConfigError, resetConfigCache } from '../config.ts';

const REQUIRED = {
  SUPABASE_URL: 'https://project.supabase.co',
  SUPABASE_SERVICE_ROLE_KEY: 'service-role-key',
  SUPABASE_ANON_KEY: 'sb_publishable_test',
  PUBLIC_APP_URL: 'https://rev-22-energia-inventory-system.vercel.app/',
  PABBLY_AUTH_EMAIL_WEBHOOK_URL: 'https://connect.pabbly.test/hook',
  PABBLY_AUTH_EMAIL_SHARED_SECRET: 'shared-secret',
  AUTH_EMAIL_FROM_ADDRESS: 'stanley@rev22.com.sg',
  AUTH_EMAIL_FROM_NAME: 'Rev 22 Global Energia',
  AUTH_EMAIL_RATE_LIMIT_HASH_SECRET: 'hash-secret',
};

const ALL_NAMES = [
  ...Object.keys(REQUIRED), 'SUPABASE_SECRET_KEY', 'SUPABASE_PUBLISHABLE_KEY',
  'AUTH_EMAIL_REPLY_TO', 'AUTH_EMAIL_TEST_CALLBACK_URLS', 'AUTH_EMAIL_TEST_ORIGINS',
  'AUTH_EMAIL_TRUSTED_PROXY_HOPS', 'AUTH_EMAIL_PABBLY_TIMEOUT_MS',
];

function withEnv<T>(values: Record<string, string>, fn: () => T): T {
  const saved = new Map(ALL_NAMES.map(n => [n, Deno.env.get(n)]));
  for (const name of ALL_NAMES) Deno.env.delete(name);
  for (const [k, v] of Object.entries(values)) Deno.env.set(k, v);
  resetConfigCache();
  try { return fn(); } finally {
    for (const name of ALL_NAMES) Deno.env.delete(name);
    for (const [k, v] of saved) if (v !== undefined) Deno.env.set(k, v);
    resetConfigCache();
  }
}

Deno.test('a complete environment loads, with sensible defaults', () => {
  withEnv(REQUIRED, () => {
    const config = loadConfig();
    assertEquals(config.publicAppUrl, 'https://rev-22-energia-inventory-system.vercel.app', 'trailing slash trimmed');
    assertEquals(config.replyTo, 'stanley@rev22.com.sg', 'reply-to defaults to the sender');
    assertEquals(config.callbackBaseUrls, [config.publicAppUrl], 'production only until test URLs are configured');
    assertEquals(config.trustedProxyHops, 1);
    assertEquals(config.pabblyTimeoutMs, 10_000, 'bounded at about ten seconds');
  });
});

Deno.test('either service-role key name works', () => {
  const { SUPABASE_SERVICE_ROLE_KEY: _drop, ...rest } = REQUIRED;
  withEnv({ ...rest, SUPABASE_SECRET_KEY: 'sb_secret_abc' }, () => {
    assertEquals(loadConfig().serviceRoleKey, 'sb_secret_abc');
  });
});

Deno.test('every required name is reported when missing — and only names', () => {
  for (const name of Object.keys(REQUIRED)) {
    const partial = { ...REQUIRED };
    delete (partial as Record<string, string>)[name];
    withEnv(partial, () => {
      const error = assertThrows(() => loadConfig(), MissingConfigError) as MissingConfigError;
      const expected = name === 'SUPABASE_ANON_KEY' ? 'SUPABASE_ANON_KEY' : name;
      assert(error.names.includes(expected), `${name} should be reported, got ${error.names.join(',')}`);
      for (const value of Object.values(REQUIRED)) {
        assert(!error.message.includes(value) || value.startsWith('https://'),
          `the error must not quote secret values: ${value}`);
      }
    });
  }
});

Deno.test('test origins are added separately, never inferred from a request', () => {
  withEnv({
    ...REQUIRED,
    AUTH_EMAIL_TEST_CALLBACK_URLS: 'https://staging.energia.test, http://localhost:3000/',
    AUTH_EMAIL_TEST_ORIGINS: 'http://localhost:3000',
  }, () => {
    const config = loadConfig();
    assertEquals(config.callbackBaseUrls, [
      'https://rev-22-energia-inventory-system.vercel.app',
      'https://staging.energia.test',
      'http://localhost:3000',
    ]);
    assertEquals(config.allowedOrigins[0], 'https://rev-22-energia-inventory-system.vercel.app');
  });
});

Deno.test('the CORS allowlist is available even when the rest of the config is not', () => {
  // Otherwise a missing secret returns a 503 with no Access-Control-Allow-Origin,
  // the browser hides the body, and a configuration mistake looks like a CORS bug.
  withEnv({ PUBLIC_APP_URL: 'https://app.example/', AUTH_EMAIL_TEST_ORIGINS: 'http://localhost:3000' }, () => {
    assertThrows(() => loadConfig(), MissingConfigError);
    assertEquals(loadAllowedOrigins(), ['https://app.example', 'http://localhost:3000']);
  });
});

Deno.test('an empty environment yields an empty allowlist, not a crash', () => {
  withEnv({}, () => { assertEquals(loadAllowedOrigins(), []); });
});

Deno.test('a dev origin is allowed for CORS without redirecting links to it', () => {
  // CORS and callbacks are configured separately on purpose: letting localhost
  // call the function is a dev convenience; letting it receive an emailed
  // verification link would put a link nobody else can open into real email.
  withEnv({ ...REQUIRED, AUTH_EMAIL_TEST_ORIGINS: 'http://localhost:3000' }, () => {
    const config = loadConfig();
    assert(config.allowedOrigins.includes('http://localhost:3000'));
    assertEquals(config.callbackBaseUrls, ['https://rev-22-energia-inventory-system.vercel.app'],
      'the emailed link must still point at production');
  });
});
