// The Edge Function's phone rules must stay identical to the browser's and the
// database's. Edge Functions cannot import from src/, so this copy is the
// compatibility contract — and a contract nobody checks is a contract that drifts.

import { assertEquals } from 'jsr:@std/assert@1';
import { normalizePhone, isValidE164 } from '../phone.ts';

const repoRoot = new URL('../../../../../', import.meta.url);
const pairs = [
  ['src/lib/customer-phones/normalize.mjs', 'supabase/functions/_shared/auth-email/phone/normalize.mjs'],
  ['src/lib/customer-phones/rules.json', 'supabase/functions/_shared/auth-email/phone/rules.json'],
];

Deno.test('the copied phone rules are byte-identical to src/lib/customer-phones', async () => {
  for (const [original, copy] of pairs) {
    const a = await Deno.readFile(new URL(original, repoRoot));
    const b = await Deno.readFile(new URL(copy, repoRoot));
    assertEquals(
      a.length === b.length && a.every((byte, i) => byte === b[i]),
      true,
      `${copy} has drifted from ${original} — re-copy it rather than editing in place`,
    );
  }
});

Deno.test('the server normalizes the numbers the affiliate form produces', () => {
  assertEquals(normalizePhone('+6591234567'), '+6591234567');
  assertEquals(normalizePhone(' +65 9123 4567 '), '+6591234567');
  assertEquals(normalizePhone('91234567'), '+6591234567');       // SG national
  assertEquals(normalizePhone('+60123456789'), '+60123456789');  // MY
  assertEquals(isValidE164('+6591234567'), true);
});

Deno.test('numbers the shared rules reject are rejected here too', () => {
  for (const bad of ['', '12345', 'not a phone', '+1', '+65123']) {
    assertEquals(normalizePhone(bad), null, bad);
  }
});
