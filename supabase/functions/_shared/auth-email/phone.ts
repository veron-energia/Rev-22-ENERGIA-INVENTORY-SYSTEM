// Phone normalization for the server, using the same rules as the browser.
//
// `phone/normalize.mjs` and `phone/rules.json` are byte-identical copies of
// `src/lib/customer-phones/`; a test fails if they drift. See phone/README.md.
//
// This is a pre-check, not the authority: `complete_affiliate_onboarding()`
// re-normalizes with the database's own `normalize_customer_phone()` when the
// affiliate finishes verifying. Rejecting an unusable number here just means the
// person finds out at the signup form instead of after clicking their email.

// @ts-ignore — plain ESM with a JSON import attribute; Deno resolves both.
import { inspectPhone, isValidE164 } from './phone/normalize.mjs';

/** E.164 for a number the shared rules accept, else null. */
export function normalizePhone(raw: string): string | null {
  const result = inspectPhone(raw) as { normalized: string | null };
  return result.normalized ?? null;
}

export { isValidE164 };
