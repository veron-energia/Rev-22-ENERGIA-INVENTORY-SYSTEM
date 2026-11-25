// The service key: the key named 'edge_functions' first, the legacy variables
// otherwise. Every value here is made up.

import { assert, assertEquals, assertFalse } from 'jsr:@std/assert@1';
import { EDGE_SECRET_KEY_NAME, loadServiceKey, resetServiceKeyAnnouncement } from './secret-key.ts';

const NAMES = ['SUPABASE_SECRET_KEYS', 'SUPABASE_SERVICE_ROLE_KEY', 'SUPABASE_SECRET_KEY'];

function withEnv<T>(values: Record<string, string>, fn: () => T): T {
  resetServiceKeyAnnouncement();
  const saved = new Map(NAMES.map(n => [n, Deno.env.get(n)]));
  for (const n of NAMES) Deno.env.delete(n);
  for (const [k, v] of Object.entries(values)) Deno.env.set(k, v);
  try { return fn(); } finally {
    for (const n of NAMES) Deno.env.delete(n);
    for (const [k, v] of saved) if (v !== undefined) Deno.env.set(k, v);
  }
}

// The helper announces its source once; keep that out of the test output except where tested.
const realLog = console.log;
console.log = (...a: unknown[]) => { if (!String(a[0]).startsWith('service key source:')) realLog(...a); };

const keys = (o: Record<string, unknown>) => JSON.stringify(o);

Deno.test('the key name is edge_functions', () => assertEquals(EDGE_SECRET_KEY_NAME, 'edge_functions'));

Deno.test('the named key is used when present, and beats both legacy variables', () => {
  withEnv({
    SUPABASE_SECRET_KEYS: keys({ default: 'sb_secret_test_default', edge_functions: '  sb_secret_test_edge_function_key_000  ' }),
    SUPABASE_SERVICE_ROLE_KEY: 'legacy-service-role',
    SUPABASE_SECRET_KEY: 'sb_secret_test_legacy',
  }, () => assertEquals(loadServiceKey(), 'sb_secret_test_edge_function_key_000'));
});

Deno.test('the named key is used even with no legacy variable at all', () => {
  withEnv({ SUPABASE_SECRET_KEYS: keys({ edge_functions: 'sb_secret_test_edge_function_key_000' }) },
    () => assertEquals(loadServiceKey(), 'sb_secret_test_edge_function_key_000'));
});

Deno.test('falls back when the variable is absent, empty or blank', () => {
  withEnv({ SUPABASE_SERVICE_ROLE_KEY: 'legacy-service-role' }, () => assertEquals(loadServiceKey(), 'legacy-service-role'));
  withEnv({ SUPABASE_SECRET_KEYS: '', SUPABASE_SERVICE_ROLE_KEY: 'legacy-service-role' }, () => assertEquals(loadServiceKey(), 'legacy-service-role'));
  withEnv({ SUPABASE_SECRET_KEYS: '   ', SUPABASE_SECRET_KEY: 'sb_secret_test_legacy' }, () => assertEquals(loadServiceKey(), 'sb_secret_test_legacy'));
});

Deno.test('falls back when the JSON is malformed or not an object', () => {
  for (const raw of ['{not json', 'sb_secret_test_edge_function_key_000', '[]', 'null', '"sb_secret_test_edge_function_key_000"', '42', '["sb_secret_test_edge_function_key_000"]']) {
    withEnv({ SUPABASE_SECRET_KEYS: raw, SUPABASE_SERVICE_ROLE_KEY: 'legacy-service-role' },
      () => assertEquals(loadServiceKey(), 'legacy-service-role', raw));
  }
});

Deno.test('falls back when the entry is missing, empty, not a string, or not sb_secret_', () => {
  const bad: unknown[] = [undefined, '', '   ', 7, null, true, ['sb_secret_test_edge_function_key_000'], { k: 'sb_secret_test_edge_function_key_000' }, 'sb_publishable_test', 'eyJhbGciOi.legacy.jwt', 'SB_SECRET_test', 'sb_secret_', 'sb_secret_short', 'sb_secret_' + 'x'.repeat(19)];
  for (const entry of bad) {
    const obj: Record<string, unknown> = { default: 'sb_secret_test_default' };
    if (entry !== undefined) obj.edge_functions = entry;
    withEnv({ SUPABASE_SECRET_KEYS: keys(obj), SUPABASE_SERVICE_ROLE_KEY: 'legacy-service-role' },
      () => assertEquals(loadServiceKey(), 'legacy-service-role', JSON.stringify(entry)));
  }
});

Deno.test('twenty characters after the prefix is enough; nineteen is not', () => {
  const ok = 'sb_secret_' + 'x'.repeat(20);
  withEnv({ SUPABASE_SECRET_KEYS: keys({ edge_functions: ok }) }, () => assertEquals(loadServiceKey(), ok));
  withEnv({ SUPABASE_SECRET_KEYS: keys({ edge_functions: 'sb_secret_' + 'x'.repeat(19) }), SUPABASE_SERVICE_ROLE_KEY: 'legacy-service-role' },
    () => assertEquals(loadServiceKey(), 'legacy-service-role'));
});

Deno.test('other key names are never used', () => {
  withEnv({ SUPABASE_SECRET_KEYS: keys({ default: 'sb_secret_test_default', pabbly: 'sb_secret_test_pabbly' }) },
    () => assertEquals(loadServiceKey(), ''));
});

Deno.test('the legacy order is unchanged: service role first, then secret key, then nothing', () => {
  withEnv({ SUPABASE_SERVICE_ROLE_KEY: ' a-service-role ', SUPABASE_SECRET_KEY: 'sb_secret_test_legacy' }, () => assertEquals(loadServiceKey(), 'a-service-role'));
  withEnv({ SUPABASE_SERVICE_ROLE_KEY: '  ', SUPABASE_SECRET_KEY: ' sb_secret_test_legacy ' }, () => assertEquals(loadServiceKey(), 'sb_secret_test_legacy'));
  withEnv({}, () => assertEquals(loadServiceKey(), ''));
});

function captured(fn: () => void): string[] {
  const lines: string[] = [];
  const originals = { log: console.log, info: console.info, warn: console.warn, error: console.error, debug: console.debug };
  for (const m of Object.keys(originals) as (keyof typeof originals)[]) {
    console[m] = (...args: unknown[]) => { lines.push(args.map(String).join(' ')); };
  }
  try { fn(); } finally { Object.assign(console, originals); }
  return lines;
}

const EDGE = 'sb_secret_test_' + 'e'.repeat(24);

Deno.test('one fixed line per instance names the source and nothing else', () => {
  withEnv({ SUPABASE_SECRET_KEYS: keys({ edge_functions: EDGE }) }, () => {
    const lines = captured(() => { loadServiceKey(); loadServiceKey(); loadServiceKey(); });
    assertEquals(lines, ['service key source: named']);
  });
  withEnv({ SUPABASE_SERVICE_ROLE_KEY: 'legacy-service-role' }, () => {
    const lines = captured(() => { loadServiceKey(); loadServiceKey(); });
    assertEquals(lines, ['service key source: legacy']);
  });
});

Deno.test('nothing but that line is logged, and it never holds key text, in any case', () => {
  const cases: Record<string, string>[] = [
    { SUPABASE_SECRET_KEYS: keys({ edge_functions: EDGE }) },
    { SUPABASE_SECRET_KEYS: '{not json ' + EDGE, SUPABASE_SERVICE_ROLE_KEY: 'legacy-service-role' },
    { SUPABASE_SECRET_KEYS: keys({ edge_functions: 'sb_publishable_test_edge' }), SUPABASE_SECRET_KEY: 'sb_secret_test_legacy_' + 'l'.repeat(20) },
    { SUPABASE_SECRET_KEYS: keys({ edge_functions: 'sb_secret_short' }), SUPABASE_SERVICE_ROLE_KEY: 'legacy-service-role' },
    {},
  ];
  for (const c of cases) {
    withEnv(c, () => {
      const lines = captured(() => { loadServiceKey(); });
      for (const l of lines) {
        assert(l === 'service key source: named' || l === 'service key source: legacy', l);
        assertFalse(l.includes('sb_secret_'));
        assertFalse(l.includes('legacy-service-role'));
      }
      assert(lines.length <= 1);
    });
  }
});
