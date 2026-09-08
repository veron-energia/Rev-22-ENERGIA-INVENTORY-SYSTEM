# Coordination note — Agent Two (Auth email delivery via generateLink → Pabbly → Gmail)

Scope: Supabase **Auth** email delivery only — affiliate signup confirmation,
resend verification, password recovery (affiliate + staff), and password-changed
security notifications. Delivery moves from Supabase's default sender to
Edge Function → `auth.admin.generateLink()` → Pabbly Connect → Gmail.

**Not touched:** invoice / payment / refund / commission code, the invoice email
path (`supabase/functions/send-invoice-email` + `src/lib/sendDoc.ts`), marketing
email, the customer-phone work (mig 161–163), and the health-survey work.

## Files I own / create (Auth-scoped, safe)

**Edge Functions — all new, under a new `_shared/auth-email` directory**
- `supabase/functions/_shared/auth-email/*.ts` — `config`, `admin`, `http`, `validate`,
  `phone`, `redirects`, `ratelimit`, `templates`, `pabbly`, `password`, `diagnostics`,
  `pipeline` (shared request envelope), `flows` (per-endpoint logic, collaborators
  injected), `liveDeps` (the real wiring), plus `tests/`.
- `supabase/functions/_shared/auth-email/phone/{normalize.mjs,rules.json}` —
  **verbatim copies** of `src/lib/customer-phones/*`, kept byte-identical by a test.
  Edge Functions cannot import from `src/`, so the copy is the compatibility contract.
- `supabase/functions/auth-signup-request/index.ts`
- `supabase/functions/auth-resend-verification/index.ts`
- `supabase/functions/auth-request-recovery/index.ts`
- `supabase/functions/auth-change-password/index.ts`
  (each is ~5 lines of wiring; the logic lives in `_shared/auth-email/flows.ts`)

**Migration — allocated number `200`** (see "Migration numbering" below)
- `supabase/200_auth_email_delivery.sql` — `public.auth_email_*` tables/functions only.
  No changes to any existing table, function, view, policy or trigger.

**Frontend — new**
- `src/lib/auth-email/client.mjs` + `client.d.mts` (repo `.mjs` + `.d.mts` convention).
- `src/pages/ForgotPasswordPage.tsx`, `src/pages/ResetPasswordPage.tsx` (staff).

**Tests / tooling — new**
- `scripts/auth-email/bootstrap-local.sh`, `local-sql.sh` — isolated Postgres on :55442.
- `scripts/auth-email/tests/{client,frontend-safety}.test.mjs`, `tests/database.mjs`.
- `scripts/auth-email/local-delivery-check.ts` — real delivery code against a local
  receiver; writes rendered email previews to `scripts/auth-email/preview/`
  (generated output, not intended for commit).

**Docs — new**
- `PABBLY_GENERATELINK_AUTH_SETUP.md`, this file.

## Status

Code, tests and documentation are complete and green locally. The Pabbly workflow
*Energia — Supabase Auth Emails* is verified and live-tested (shared-secret
rejection blocked at the filter; Gmail confirmed sending as
`stanley@rev22.com.sg`). Nothing is deployed and no production Auth setting has
been changed. Remaining: apply migration 200, run
`scripts/auth-email/deploy.sh`, add the `/reset-password` redirect URL, deploy the
frontend. Details in `PABBLY_GENERATELINK_AUTH_SETUP.md` §10 and §12.

**Note on `.env`** — I appended six server-side values (PUBLIC_APP_URL, the
Pabbly shared secret, the three AUTH_EMAIL_FROM/REPLY values and a rate-limit
hash secret) next to the webhook URL that was already there. `.env` is gitignored
and Vite inlines only `VITE_`-prefixed values, verified by scanning a fresh
`dist/`. If you also use `.env`, these are additive and all prefixed
`AUTH_EMAIL_`/`PABBLY_AUTH_EMAIL_`/`PUBLIC_APP_URL`.

## Shared files touched — please review before editing the same lines

| File | Change | Lines |
|---|---|---|
| `src/App.tsx` | 2 imports + 2 public routes: `/forgot-password`, `/reset-password` | import block, public-route block near `/affiliate/*` |
| `package.json` | 5 scripts, all `*auth-email*`: `test:auth-email`, `:edge`, `:db`, `:delivery`, `check:auth-email`. **No dependency changes.** | `scripts` block only |
| `src/pages/AffiliateJoinPage.tsx` | `supabase.auth.signUp` → `auth-signup-request`; adds a resend action | whole submit path |
| `src/pages/AffiliateForgotPasswordPage.tsx` | `resetPasswordForEmail` → `auth-request-recovery` | whole submit path |
| `src/pages/AffiliateResetPasswordPage.tsx` | `updateUser({password})` → `auth-change-password` | whole submit path |
| `src/pages/AffiliateAccountPage.tsx` | `updateUser({password})` → `auth-change-password` | `changePw` only |
| `src/pages/LoginPage.tsx` | adds a "Forgot password?" link | below the submit button |

None of these are invoice/payment/refund files.

## Shared files deliberately NOT touched

- `src/context/AuthContext.tsx` — unchanged. `signInWithPassword` is not an
  email-triggering call; session handling is unchanged.
- `src/lib/supabase.ts` — unchanged. The client stays on its current settings
  (verified: `flowType = 'implicit'`, `detectSessionInUrl = true`), which is what
  makes admin-generated action links work on a second device.
- `src/lib/customer-phones/*` — unchanged (copied, not moved).
- `supabase/functions/send-invoice-email/index.ts`, `src/lib/sendDoc.ts` — unchanged.
- `src/pages/AffiliateVerifyPage.tsx` — unchanged. The onboarding RPC contract and
  the localStorage/`need_details` cross-device fallback both still hold.
- `src/pages/InvoicesPage.tsx`, `DashboardPage.tsx`, `ReportsPage.tsx` — untouched
  (agent one has uncommitted edits in all three).
- No existing migration edited. No `npm ci` / `npm install` run — no dependency change
  is needed, so shared `node_modules` is never rewritten.

## Migration numbering

Agent one's invoice series runs `170–179`. I have deliberately **skipped 180–199**
and taken **`200_auth_email_delivery.sql`** so the invoice series can keep growing
without a collision. Ordering is safe: mig 200 depends on nothing but a stock
`public` schema and `auth.users`, and nothing else depends on it.

## Isolated test database

Agent one's disposable target is `PGPORT=55441 PGDATABASE=energia_invoice_test`
(`scripts/invoices/local-sql.sh`). Mine is **`PGPORT=55442`,
`PGDATABASE=energia_auth_email_test`**, in its own datadir. I never connect to
production and never reset a shared database.

## Preserved

Affiliate onboarding + `complete_affiliate_onboarding` contract, referral ownership,
roles, commissions, claims, dedupe, the customer phone/name rules (mig 161–163) and
the completed health-survey changes.
