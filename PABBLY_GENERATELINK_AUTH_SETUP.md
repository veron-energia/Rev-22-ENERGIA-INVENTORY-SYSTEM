# Energia Auth email — Supabase `generateLink()` → Pabbly → Gmail

Verification, recovery and password-change emails now leave through a Supabase
Edge Function and Pabbly Connect instead of Supabase's built-in sender.

**Supabase still owns everything that matters.** Users, password hashing,
verification and recovery tokens, link expiry, session issuing and token
validation are all unchanged. What changed is who carries the message. Pabbly and
Gmail are the postman; they make no decisions about accounts.

> **Status: Pabbly verified and live-tested; Supabase side not yet deployed.**
> The workflow *Energia — Supabase Auth Emails* exists, is Active, is correctly
> configured, and has been tested end to end — including a shared-secret
> rejection that Gmail never saw. The sender question in §7 is **resolved for
> today**: Gmail's own API response shows `From: Rev 22 Global Energia
> <info@rev22.com.sg>`, not the personal address.
>
> Still to do: apply the migration, set the secrets, add one redirect URL, deploy
> the four functions, then the frontend. See
> [What is not done](#12-what-is-not-done-yet).

---

## 1. Architecture

```
Browser  ──POST──▶  Edge Function                     ▶ nothing sensitive returns
                    ├─ request envelope + field whitelist
                    ├─ atomic rate limit  (Postgres, migration 200)
                    ├─ auth.admin.generateLink()  ──▶ Supabase Auth
                    │     creates/keeps the user, mints the token
                    ├─ render the email (template + link)
                    └─ POST ──▶ Pabbly webhook ──▶ Gmail ──▶ recipient
                                 checks the shared secret first
```

The browser never sees a generated link, a token, the service-role key, the
Pabbly webhook URL or the shared secret. It gets `{ ok, status, request_id }`.

### Implemented flows

| Flow | Endpoint | Callback |
|---|---|---|
| Affiliate signup confirmation | `auth-signup-request` | `/affiliate/verify` |
| Affiliate resend verification | `auth-resend-verification` | `/affiliate/verify` |
| Password recovery (affiliate) | `auth-request-recovery` (`flow: "affiliate"`) | `/affiliate/reset-password` |
| Password recovery (staff) | `auth-request-recovery` (`flow: "staff"`) | `/reset-password` |
| Password-changed notification | `auth-change-password` | — (no link in the email) |

Invitations, magic links and email-change flows are **out of scope** and were not
built: none existed, and adding endpoints nobody calls would be new attack
surface for no benefit. The shared module extends to them without rework.

Non-Auth email is untouched. `supabase/functions/send-invoice-email` and
`src/lib/sendDoc.ts` still go through Resend exactly as before.

---

## 2. The API strategy, and why

`admin.generateLink()` behaves differently per type and per account state. The
design below follows the behaviour in Supabase Auth's own
`adminGenerateLink` handler ([internal/api/mail.go](https://github.com/supabase/auth/blob/master/internal/api/mail.go)),
which is what makes the resend path safe rather than merely convenient.

### Signup — `type: "signup"`

| Account state | What the server does | What the caller sees |
|---|---|---|
| No account | `generateLink({type:'signup', email, password, options:{data, redirectTo}})` — creates the user, mints a confirmation token | `{ok:true, status:"submitted"}` |
| Exists, unverified | Treated as a **resend** (see below) | identical |
| Exists, verified | Nothing is sent | identical |

### Resend — the important one

**Resend of a signup confirmation is safely supported**, and no compromise was
needed. This was checked against the Auth source rather than assumed:

* For `type: "signup"` where the user already exists, the password is read
  **only** on the branch that creates a user. An existing account's password is
  never touched — so `regenerateSignupLink()` passes an empty password. That
  empty value is also what makes the call fail closed: if the account vanished
  between the state check and the call, the create branch rejects an empty
  password instead of quietly creating an account from a resend request.
* Metadata is merged, not replaced, and only when `data` is supplied. Resend
  supplies none, so an unauthenticated retry cannot rewrite a pending account's
  name, phone or role.
* A **verified** account returns `email_exists`, which the server turns into a
  silent no-op.

So resend needs none of the unsafe shortcuts: no delete-and-recreate, no signup
re-submission to reset a password, no metadata overwrite, no auto-confirm, no
fabricated token, and no magic-link fallback.

Belt and braces: `auth_email_user_state()` is consulted first, so a resend for an
unknown address never reaches `generateLink()` at all.

### Recovery — `type: "recovery"`

Returns `404 user_not_found` for an address with no account. The server absorbs
that and answers exactly as it does for a real account.

### Password change — no `generateLink` involved

`auth-change-password` performs the change itself with `PUT /auth/v1/user` using
**the caller's own access token**, then sends the notification. This is the only
way the notification can be trusted: the server saw Supabase confirm the change
rather than taking a browser's word for it. Every Supabase rule still applies —
session validity, recovery-session semantics, the project password policy, any
reauthentication requirement. The admin user-update API is deliberately not used;
it would bypass all of that.

The new password does pass through the function on its way to Supabase — the
same TLS hop the browser would have made. It is never logged or stored.

### Callback and session behaviour

The client is on `flowType: 'implicit'` (verified: `createClient` with no auth
options resolves to implicit, `detectSessionInUrl: true`). Admin-generated links
carry **no PKCE verifier**, so:

* **Same device** — works as before.
* **Another device or browser** — also works, because there is no verifier to be
  missing. This is an improvement on the previous browser-initiated `signUp()`
  path. `AffiliateVerifyPage` already handles the cross-device case: with no
  `localStorage` onboarding details it shows the "Confirm your details" form.

---

## 3. Server-side configuration

Set as Supabase Function secrets. **None of these has, or may ever have, a
`VITE_` equivalent** — a `VITE_` value is compiled into the public bundle.

| Name | Notes |
|---|---|
| `SUPABASE_URL` | Injected by the platform. |
| `SUPABASE_SERVICE_ROLE_KEY` | Injected. This project uses the new API keys (`sb_publishable_…`), so `SUPABASE_SECRET_KEY` is accepted as the equivalent — the function takes whichever is present. |
| `SUPABASE_ANON_KEY` | Injected; `SUPABASE_PUBLISHABLE_KEY` also accepted. Used as the `apikey` when acting *as the user* in `auth-change-password`. |
| `PUBLIC_APP_URL` | `https://rev-22-energia-inventory-system.vercel.app` |
| `PABBLY_AUTH_EMAIL_WEBHOOK_URL` | The **Energia Auth Emails** workflow's webhook. Not the invoice or marketing one. |
| `PABBLY_AUTH_EMAIL_SHARED_SECRET` | Long random string. Generate with `openssl rand -base64 48`. |
| `AUTH_EMAIL_FROM_ADDRESS` | `info@rev22.com.sg` |
| `AUTH_EMAIL_FROM_NAME` | `Rev 22 Global Energia` |
| `AUTH_EMAIL_REPLY_TO` | `info@rev22.com.sg` (defaults to the from address) |
| `AUTH_EMAIL_RATE_LIMIT_HASH_SECRET` | HMAC key for the rate-limit keys. `openssl rand -base64 48`. Rotating it resets the counters. |

Optional:

| Name | Default | Notes |
|---|---|---|
| `AUTH_EMAIL_TEST_ORIGINS` | — | Extra CORS origins, comma-separated. |
| `AUTH_EMAIL_TEST_CALLBACK_URLS` | — | Extra callback bases for staging. A request's `Origin` must match one exactly to be used. |
| `AUTH_EMAIL_TRUSTED_PROXY_HOPS` | `1` | See [§9](#9-a-note-on-the-client-ip). |
| `AUTH_EMAIL_PABBLY_TIMEOUT_MS` | `10000` | Bounded wait for Pabbly. |

`.env` in the repo root now carries all seven of the values you must set, ready
for `scripts/auth-email/deploy.sh`. That file is gitignored, and Vite only inlines
`VITE_`-prefixed values into the bundle — verified by building and scanning
`dist/` for each one. It is **not** how the deployed functions read
configuration; they read Supabase Function secrets. It is a staging area for
setting them.

---

## 4. Rate limiting

Thresholds live in one table, `public.auth_email_limits`, and are read on every
request. Changing a limit is an `UPDATE`; no redeploy.

| Action | Scope | Limit |
|---|---|---|
| signup | normalized email | 3 per 15 min |
| signup | client IP | 30 per hour |
| resend | normalized email | 3 per 15 min |
| resend | client IP | 30 per hour |
| recovery | normalized email | 5 per hour |
| recovery | client IP | 60 per hour |
| *combined* (all three) | client IP | 60 per hour |

```sql
-- Raise the per-IP signup ceiling for a big roadshow:
update public.auth_email_limits
   set max_attempts = 60, updated_at = now()
 where action = 'signup' and scope = 'ip';
```

Sizing: ten people on one roadshow Wi-Fi doing a signup, a resend and a recovery
each is 30 requests — inside every ceiling. Verified by test.

Properties, each covered by a test in `scripts/auth-email/tests/database.mjs`:

* **Atomic.** One transaction-scoped advisory lock wraps check-then-insert, so
  eight concurrent requests for a 3-slot bucket admit exactly three.
* **Claimed before anything happens.** The reservation is taken before a link is
  generated and before Pabbly is contacted, and is **never refunded** — a failed
  send, an unknown address and a rejected provider call all cost a slot. That is
  what caps retries.
* **Refusals do not extend the lockout.** Hammering a full bucket adds no events,
  so a legitimate user's wait does not keep growing.
* **Fails closed.** If the limiter cannot answer, the endpoint returns 503 and
  sends nothing.
* **Email limits are mandatory.** With no trustworthy IP, the email buckets still
  apply.
* **Hashed keys.** Emails and IPs are stored only as HMACs.
* **Service-role only.** RLS on, no policies, all grants revoked from `anon` and
  `authenticated`.
* **Retention ~14 days**, via `select public.auth_email_cleanup();` — schedule it
  daily under Supabase → Integrations → Cron. Until it is scheduled the tables
  grow slowly and nothing breaks; every count is bounded by the window, not by
  table size.

---

## 5. Pabbly workflow — "Energia — Supabase Auth Emails"

**This already exists and is correctly configured.** It lives in the *Rev22
Energia* folder, is Active, and its webhook is the one already in `.env`
(verified: same URL, byte for byte). Nothing else in the account was touched.

Verified configuration, read from the live workflow on 8 Sep 2026:

| Step | App / Event | State |
|---|---|---|
| 1 | Webhook by Pabbly → Catch Webhook (Preferred) | Response captured |
| 2 | Filter (Pabbly) → Filter Values | `delivery_secret` **Equals** a 64-character secret |
| 3 | Gmail → Send Email | Connected, mapped (below) |

Gmail step field mapping, as configured:

| Gmail field | Mapped to | Note |
|---|---|---|
| Sender Name | `from_name` | |
| **Sender Email Address** | `stanley@rev22.com.sg` — **stale, see below** | Chosen from the dropdown, not typed. Must become `info@rev22.com.sg`, but only as part of reconnecting the Gmail account (§7a fix 1) |
| Recipient Email Addresses | `to` | |
| Reply To | `reply_to` | |
| Email Subject | `subject` | |
| Email Content | `html` | |
| Email Content Type | HTML | |
| Labels | INBOX | |

The step order matters and is correct: the filter sits **between** the trigger
and Gmail, so a request that fails the secret check never reaches a sending step.

The sections below describe how to rebuild it from scratch, should it ever be
lost. Do not touch the invoice or marketing workflows.

### Rebuilding it from scratch

**Step 1 — Trigger: Webhook by Pabbly → Catch Webhook.**
Copy the generated URL into `PABBLY_AUTH_EMAIL_WEBHOOK_URL`. Send one test
request to capture the field names:

```bash
curl -X POST "<the webhook URL>" -H 'Content-Type: application/json' -d '{
  "delivery_secret":"<the shared secret>",
  "request_id":"00000000-0000-4000-8000-000000000000",
  "action_type":"verify_signup",
  "to":"shinthantstanley@gmail.com",
  "from_name":"Rev 22 Global Energia",
  "from_email":"info@rev22.com.sg",
  "reply_to":"info@rev22.com.sg",
  "subject":"Verify Your Energia Affiliate Account",
  "html":"<p>capture only</p>","text":"capture only",
  "recipient_role":"affiliate"
}'
```

**Step 2 — Filter, before any sending step.**
`delivery_secret` **Equals** the shared secret. Nothing downstream runs unless it
matches. Put this immediately after the trigger — a filter placed after the Gmail
step protects nothing.

The existing workflow's secret has been copied into your local `.env` as
`PABBLY_AUTH_EMAIL_SHARED_SECRET`, so the Supabase side will match without
anyone retyping it. Do not rotate it on one side only: change the filter value
and the Supabase secret together, or sending stops.

**Step 3 — Action: Gmail → Send Email.** Map:

| Gmail field | Value |
|---|---|
| To | `{{to}}` |
| Sender / From name | `{{from_name}}` |
| From address (if the action offers one) | `{{from_email}}` — see [§7](#7-sender-compatibility-the-one-real-blocker) |
| Reply To | `{{reply_to}}` |
| Subject | `{{subject}}` |
| Content type | HTML |
| Email body | `{{html}}` |

Do not add a second Gmail step for the plain-text part; `text` is carried for
clients that need it and for troubleshooting.

**Payload reference**

| Field | Meaning |
|---|---|
| `delivery_secret` | Checked in step 2, then ignored |
| `request_id` | UUID; also sent as an `Idempotency-Key` header |
| `action_type` | `verify_signup` \| `password_recovery` \| `password_changed` |
| `to` | Recipient, read back from the Supabase account |
| `from_name`, `from_email`, `reply_to` | Server-configured; never from the browser |
| `subject`, `html`, `text` | Fully rendered server-side |
| `recipient_role` | `affiliate` \| `staff` — for routing or reporting only |

The Supabase action link is inside `html`/`text`. There is no separate token or
link field: one copy is enough, and fewer copies is less exposure.

### The sender is changing to `info@rev22.com.sg`

Server-side configuration has already been switched: `AUTH_EMAIL_FROM_ADDRESS`
and `AUTH_EMAIL_REPLY_TO` are `info@rev22.com.sg`, and every test and fixture
with it. The sender was never hardcoded anywhere in the function source — it is
configuration, so this was a one-line change plus fixtures.

**The Pabbly Gmail step has deliberately not been touched**, and it still reads
`stanley@rev22.com.sg`. Changing that one field on the current connection would
be the wrong move, for two reasons:

1. **It would not fix deliverability.** The Gmail step is connected to a personal
   Gmail account. Whatever address sits in that field, Google signs the message
   with the *connected account's* domain — `d=gmail.com` — so DMARC alignment
   against `rev22.com.sg` still fails and Outlook still junks it. Changing the
   field changes the label on the envelope, not who signed it.
2. **It could silently send from the personal address.** If
   `info@rev22.com.sg` is not a verified send-as alias on that personal account,
   Gmail rewrites `From` to the personal Gmail address without warning. That is
   the one outcome ruled out from the start, so it is not worth risking on the
   chance that the alias happens to exist.

Both problems have the same answer, which is §7a fix 1: **reconnect the Gmail
step to the `info@rev22.com.sg` Google account itself.** Then `info@` is the
sending account rather than a costume, Google signs as `rev22.com.sg`, and the
sender change and the deliverability fix land together.

That reconnection needs a Google sign-in, so it is yours to do:

1. Pabbly → *Energia — Supabase Auth Emails* → the Gmail step → **Connections**.
2. Add a connection, signing in as **info@rev22.com.sg** (or a `rev22.com.sg`
   account that has `info@` as an alias — same-domain aliases align fine).
3. Back on **Action Setup**, set **Sender Email Address** to `info@rev22.com.sg`.
   It should now be in the dropdown; if it is not, the connection is still the
   personal account.
4. Leave every other mapping alone — `to`, `reply_to`, `subject`, `html` and the
   HTML content type are already correct and are unaffected by the sender.
5. Save, then re-run the live test in §11 and check the received headers.

### What Pabbly can see, and for how long

Pabbly necessarily receives the whole email, **including the verification or
recovery link**, and stores it in workflow history. Pabbly's privacy policy states
that Connect data older than 15 days is removed automatically. Treat that as the
exposure window: for up to 15 days, anyone with access to that Pabbly account can
read a link that was live when it was sent.

Practical mitigations, in order of effect:

1. Keep the Pabbly account's own login secured — it is now an Auth-adjacent
   credential.
2. Supabase link expiry does the real work. A link that has been used or has
   expired is inert in history.
3. Delete individual task-history entries after testing if the account offers it.

The password-changed notification carries no link at all, so its history entry is
harmless.

The 15 days is confirmed in the product itself, not just the policy: the Task
History page states that task history is only available for the last 15 days.

**Not verified:** whether this plan can shorten retention below 15 days, or delete
an individual task-history entry. Neither control was found while configuring the
workflow. Treat 15 days as the exposure window unless you find otherwise.

---

## 6. Public endpoint protection

CORS is a browser courtesy and the Pabbly secret protects the *workflow*; neither
authenticates a signup request. What actually guards these endpoints:

* POST only; `application/json` only; 8 KB ceiling enforced on the read, not on a
  `Content-Length` the caller supplies.
* A strict field whitelist. An unknown key is a **400**, not an ignored field —
  so `role`, `subject`, `html`, `to`, `from_email` and `redirect_to` are refused
  loudly rather than silently dropped.
* Recipients, subjects, sender and templates are server-owned. The recipient is
  read back from the Supabase account, never from the request.
* Redirects come from a three-entry allowlist keyed by a flow name. There is no
  code path from caller text to a redirect.
* Generated links are validated against this project's Auth origin before being
  put into an email.
* Database-backed atomic rate limiting (§4).
* A bounded 10-second wait on Pabbly.
* CORS echoes only allowlisted origins — and an unlisted origin still gets a
  correct response, it just gets no CORS grant.

This is not an open relay: there is no combination of inputs that makes it send
chosen content to a chosen address.

**Gateway JWT verification** — deploy the three public endpoints with
`--no-verify-jwt` (nobody signing up has a session). Deploy
`auth-change-password` **without** that flag; it also verifies the token itself,
so it is safe either way.

---

## 7. Sender compatibility — resolved for today, dated for 2027

**Requested:** Pabbly's Gmail action, connected to a personal Gmail account,
sending as `info@rev22.com.sg`.

> **Correction, 8 Sep 2026.** The brief described `rev22.com.sg` as hosted by
> another email provider. Its MX records point at `aspmx.l.google.com` — the
> domain's mail is on **Google**. That matters twice over: it makes the January
> 2027 concern below far less likely to apply, and it means the deliverability
> fix in §7a is straightforward. Confirm the mailbox type in the Google Admin
> console before relying on either.

### It works today. This is evidence, not a claim.

Two independent findings from the live workflow:

1. **The Gmail action exposes a Sender Email Address field**, and it is set to
   `info@rev22.com.sg`. Its "Map" toggle is **off**, which means the address
   was *selected from the dropdown Pabbly fetches from the connected Gmail
   account* rather than typed in. Gmail only offers verified "send mail as"
   aliases there — so the alias is verified on that account.

2. **Gmail's own API response confirms the header was not rewritten.** The saved
   response on the Gmail step, from a send on 4 Sep 2026, contains:

   ```
   From:     Rev22 Energia <info@rev22.com.sg>
   To:       shinthantstanley@gmail.com
   Reply-To: info@rev22.com.sg
   Content-Type: text/html; charset=UTF-8
   ```

   If the alias were unverified, Gmail would have silently rewritten `From` to
   the personal address. It did not.

Note the sender *name* in that older test was `Rev22 Energia`. It is mapped to
`{{from_name}}`, so the value now sent is `AUTH_EMAIL_FROM_NAME` —
**Rev 22 Global Energia**. Confirm this on the next received message.

### It stops working in January 2027.

Google's support page states that from January 2027 Gmail will not support
"Send as" for third-party email addresses, and says the change does not apply to
Google Workspace aliases or other Gmail addresses you own.

Given the MX correction above, `info@rev22.com.sg` looks like a **Google**
address, which would put it in the exempt group rather than the retired one. That
is a reasonable inference from the MX records, not a confirmed fact — verify the
mailbox in the Google Admin console.

Either way it stops mattering once §7a fix 1 is done: connecting Pabbly to that
mailbox directly is not "send as" at all.

**The decision is still yours, and nothing was changed to pre-empt it.** No
mailbox provider, no DNS, no Gmail account-wide default:

1. **Google Workspace on `rev22.com.sg`** — the durable answer, since Workspace
   "send as" for a domain you own is explicitly unaffected. Needs the domain's
   MX/DNS arrangement decided.
2. **Carry on as-is until the deadline.** Everything works now; put a reminder
   somewhere for late 2026.
3. **Send from the personal Gmail address with `Reply-To: info@rev22.com.sg`.**
   Works indefinitely, but recipients see the personal address. Listed because it
   is a real option, not because it is being done.

SMTP, Resend and SendFox for Auth were excluded by you and were not considered.

## 7a. Deliverability — why Outlook junks it and Yahoo drops it

Observed on 8 Sep 2026: mail to an `outlook.com` address landed in Junk, and mail
to a `yahoo.com` address never arrived at all. That pattern is not a content
problem and not a code problem. It is a sending-domain authentication problem.

### What the domain publishes

```
scripts/auth-email/check-deliverability.sh
```

At the time of writing, `rev22.com.sg` publishes **zero TXT records**:

| Record | State | Effect on a receiver |
|---|---|---|
| MX | `aspmx.l.google.com` — Google | fine |
| **SPF** | **absent** | no server is declared as allowed to send as the domain |
| **DKIM** | **absent** | nothing is signed as the domain |
| **DMARC** | **absent** | no stated policy, so receivers fall back to their own judgement |

Since February 2024 both Yahoo and Google have required SPF, DKIM and DMARC from
bulk senders, and Outlook weighs the same signals. An unauthenticated message
carrying a company domain in `From` is exactly the shape of a spoof, so Outlook
files it under Junk and Yahoo declines it quietly. The receivers are behaving
correctly; the domain is the thing that is missing.

### The deeper cause, which SPF alone will not fix

The mail is sent by a **personal Gmail account** using "send as"
`info@rev22.com.sg`. Google signs outgoing mail with the *sending account's*
domain, so the signature says `d=gmail.com`, and the envelope sender is the
personal address too.

DMARC requires the authenticated domain to **align** with the domain in `From`.
`gmail.com` does not align with `rev22.com.sg`. So even after SPF and DKIM are
published for `rev22.com.sg`, mail sent this way still fails alignment — because
nothing about it was ever signed as `rev22.com.sg`.

### Fixes, in order of effect

**1. Connect Pabbly's Gmail step to the `info@rev22.com.sg` mailbox itself,
not to a personal Gmail sending as it.**

The MX records show the domain is on Google, so that mailbox is a Google account
and Pabbly can connect to it directly. Then Google signs as `rev22.com.sg`,
alignment holds, and the whole problem disappears. No DNS change is needed for
this step, and it is the single highest-impact change.

It also removes the January 2027 exposure in §7 outright, since that retirement
targets personal-Gmail "send as" for third-party addresses.

**2. Enable DKIM for the domain.** Google Admin → Apps → Google Workspace →
Gmail → Authenticate email → generate a key for `rev22.com.sg`, then publish the
`google._domainkey` TXT record it gives you and click Start authentication.

**3. Publish SPF.** A TXT record on `rev22.com.sg`:

```
v=spf1 include:_spf.google.com ~all
```

If anything else legitimately sends as this domain, add it before `~all`.

**4. Publish DMARC**, starting in monitoring mode. A TXT record on
`_dmarc.rev22.com.sg`:

```
v=DMARC1; p=none; rua=mailto:info@rev22.com.sg; fo=1
```

Read the aggregate reports for a fortnight, confirm only legitimate sources
appear, then tighten to `p=quarantine` and later `p=reject`. Do not start at
`reject` — that turns a misconfiguration into lost mail.

**None of these were done for you.** They are DNS and mail-provider changes, and
they were explicitly outside what was authorized.

### Confirming the fix

Send to a Gmail address and open **Show original**. You want:

```
SPF:   PASS   with domain rev22.com.sg
DKIM:  PASS   with domain rev22.com.sg      <- the domain matters
DMARC: PASS
```

`DKIM: PASS with domain gmail.com` means fix 1 has not been done — the message is
still being sent by the personal account, and alignment still fails no matter
what the DNS says.

### A smaller, secondary point

Pabbly's Gmail step sends `Content-Type: text/html` only. The function already
renders a plain-text alternative and includes it in the payload as `text`, but
the Gmail action has no field for it, so the delivered message is HTML-only.
Multipart messages score marginally better with filters. This is worth perhaps a
percent next to authentication, and there is no way to fix it inside Pabbly's
Gmail action — it would need a different sending step. Not worth doing until the
four fixes above are in place.

## 8. Callback URLs

Add under Supabase → Authentication → URL Configuration → Redirect URLs. **This
is a production Auth setting; it has not been changed.**

```
https://rev-22-energia-inventory-system.vercel.app/affiliate/verify
https://rev-22-energia-inventory-system.vercel.app/affiliate/reset-password
https://rev-22-energia-inventory-system.vercel.app/reset-password        ← new
```

The first two already exist for the current flows. `/reset-password` is new
(staff recovery). If a redirect is not on the allowlist, Auth silently falls back
to the Site URL and the link lands on the wrong page — a quiet failure worth
checking first.

Keep the **Email** provider enabled and **Confirm email** on. Turning confirmation
off would let unverified accounts straight in.

---

## 9. A note on the client IP

The IP is read **only** from the entry of `x-forwarded-for` that our own proxy
wrote — counting from the right, since a caller can prepend anything. Headers
that have not been verified as platform-written (`x-real-ip`, `true-client-ip`)
are not consulted at all.

`AUTH_EMAIL_TRUSTED_PROXY_HOPS` defaults to `1` (the last entry). **Confirm the
real hop count from a live request before relying on IP limits.** Deploy, send
one request, and read the `ip_seen` field in the function log:

* `ip_seen: true` — an IP was accepted; the per-IP limits are live.
* `ip_seen: false` — nothing trustworthy was found. Requests are still limited by
  the mandatory per-email buckets. Adjust the hop count and re-check.

---

## 10. Rollout order

Steps 2 and 3 are **already done**. Each remaining step is safe to stop after.
The frontend is deliberately last: it is the only step that starts sending
traffic at the new endpoints.

1. **Migration.** Paste `supabase/200_auth_email_delivery.sql` into the SQL
   editor and run it. Its verification block raises if anything is missing or
   reachable by `anon`. Do this first — the functions fail closed until the
   rate-limit tables exist.
2. ~~**Pabbly workflow.**~~ Done. *Energia — Supabase Auth Emails*, Active,
   verified, live-tested (§5, §11).
3. ~~**Gmail alias.**~~ Verified working today (§7). The 2027 decision is
   separate and does not block anything now.
4. **Secrets and functions** — one command:

   ```bash
   npx supabase login                      # you; opens a browser
   scripts/auth-email/deploy.sh --project-ref jknfhpgryywsrzdstqzy
   ```

   It reads the seven server-side values from `.env` (already populated,
   including the shared secret copied from the live Pabbly filter), never prints
   them, sets them on the project, and deploys all four functions with the right
   `--no-verify-jwt` flags. Add `--dry-run` first to see exactly what it will do.

5. **Callback URL.** Authentication → URL Configuration → Redirect URLs, add
   `https://rev-22-energia-inventory-system.vercel.app/reset-password` (§8).
   The other two are already there.
6. **Verify.**

   ```bash
   node scripts/auth-email/verify-deployed.mjs \
     --url https://jknfhpgryywsrzdstqzy.supabase.co \
     --anon-key <the publishable key from .env>
   ```

   Safe by default — every probe is malformed or aimed at an address with no
   account, so nothing is created and no email is sent. Add `--send-test-email`
   for the one authorized live send.
7. **Frontend.** Deploy last.
8. **Cron.** Schedule `select public.auth_email_cleanup();` daily under
   Supabase → Integrations → Cron.

## 10a. Testing from the local dev server

The Vite dev server runs on `http://localhost:3000`, which is a different origin
from the deployed app, so the functions must be told to accept it. `.env` already
carries:

```
AUTH_EMAIL_TEST_ORIGINS=http://localhost:3000
```

`deploy.sh` forwards it. Two things worth being clear about:

* **This is CORS only.** The verification and recovery links in the emails still
  point at `PUBLIC_APP_URL`. Callback bases are configured separately
  (`AUTH_EMAIL_TEST_CALLBACK_URLS`) and localhost is deliberately **not** in that
  list — an emailed link pointing at `localhost:3000` is a link nobody but the
  sender can open, and `Origin` can be set by anything that speaks HTTP, so a
  localhost callback is worth adding only while you are actively using it.
* **Remove the line when you stop testing locally**, and redeploy. It is a small
  standing allowance on a production function.

Until the functions are deployed, the local form will report "We could not reach
the server" — see §14, which tells you how to tell that apart from a real
connection problem.

## 11. Verification

### Local — all of this passes now

```bash
npm run typecheck              # frontend
npm run build                  # frontend production build
npm run check:auth-email       # deno check, all four Edge Functions
npm run test:auth-email:edge   # 78 Deno tests over the shared module
npm run test:auth-email        # 17 Node tests: response handling + leak scan
npm run test:auth-email:delivery   # real delivery code against a local receiver

scripts/auth-email/bootstrap-local.sh start   # isolated Postgres on :55442
npm run test:auth-email:db                    # migration 200, incl. concurrency
scripts/auth-email/bootstrap-local.sh destroy
```

`test:auth-email:delivery` also writes readable copies of all three emails to
`scripts/auth-email/preview/` (generated output; not meant to be committed).

### Live Pabbly tests — already run, 8 Sep 2026

```bash
deno run --allow-env --allow-read --allow-net scripts/auth-email/live-pabbly-test.ts \
  --confirm --to tiktokautomationtryout@gmail.com --first Stanley --last Aung
```

Recipients come from an allowlist in the script — currently
`shinthantstanley@gmail.com` and `tiktokautomationtryout@gmail.com`. Anything else
is refused, so the script cannot later be pointed at an arbitrary address.

Each run posts two requests to the live webhook, both carrying an email rendered
by the same template the Edge Function uses. Both get `200 {"status":"success",
"message":"Webhook received"}` from the listener — which is the point of the
exercise, because those two identical responses had opposite outcomes:

| Run | Request | Secret | Pabbly task history |
|---|---|---|---|
| 13:45 → `shinthantstanley@` | `049c1871…` | wrong | **2 Steps** — trigger + filter, then stopped |
| 13:45 → `shinthantstanley@` | `8fa05d8d…` | correct | **3 Steps** — trigger + filter + Gmail |
| 13:54 → `tiktokautomationtryout@` | `4d74a1a8…` | wrong | **2 Steps** — trigger + filter, then stopped |
| 13:54 → `tiktokautomationtryout@` | `d2f464f9…` | correct | **3 Steps** — trigger + filter + Gmail |

Run twice, to two different inboxes, with the same result — so the filter's
behaviour is reproducible rather than a one-off. The second run also delivers to
an address that is **not** the connected Gmail account itself, which is the more
honest test of external delivery.

**The shared-secret rejection works, and the rejected request never reached a
sending step.** That is the workflow's own accounting, not an inference: a
blocked request costs two steps, a delivered one costs three.

It also demonstrates the distinction this system is built around — an HTTP 2xx
from the webhook is not evidence that anything was sent.

**Still needs a human at the inbox** — both `shinthantstanley@gmail.com` and
`tiktokautomationtryout@gmail.com` — because "observed at the recipient" is the
one thing no API can confirm:

* exactly **one** new message should have arrived, subject ending `[delivery test]`;
* the one ending `[SHOULD NOT ARRIVE]` must **not** be there — if it is, the
  filter is not protecting the workflow and nothing should be deployed;
* on the delivered one, *Show original* → `From: Rev 22 Global Energia
  <info@rev22.com.sg>` and `Reply-To: info@rev22.com.sg`.

The link inside that message is deliberately not a working token: minting a real
one needs the service-role key, which exists only in the deployed function. Real
link testing is in the list below.

### After deploying — do these before switching traffic over

1. ~~**The real `From` and `Reply-To`.**~~ Confirmed in §7 from Gmail's own API
   response, and again by the 8 Sep live test — subject to your inbox check above.
2. ~~**Shared-secret rejection.**~~ Confirmed above: blocked at the filter,
   Gmail never ran.
3. **A real link, end to end.** Sign up a disposable address, click the link, and
   confirm onboarding completes.
4. **Cross-device.** Open the same link in a different browser. It should work —
   admin links carry no verifier.
5. **Expired / reused.** Click a used link again; expect Supabase's
   already-used behaviour and the "expired or already used" screen.
6. **Recovery both ways.** Staff via `/forgot-password`, affiliate via
   `/affiliate/forgot-password`. Set a password, then sign in with it.
7. **Notification.** After a reset, confirm the "Your Energia Password Was
   Changed" email arrives with no link in it.
8. **Rate limit.** Four signups for one address inside 15 minutes; the fourth
   must return 429 with friendly wording.
9. **`ip_seen`** in the logs (§9).

### What the local tests do and do not prove

They prove the logic: what is sent, what is refused, what is suppressed, what the
limiter admits under concurrency, and that no secret or link reaches a response,
a log or the bundle. The delivery check exercises the **real** delivery code
against a local stand-in, so the payload and the secret-rejection path are
verified for real.

They prove nothing about deployed behaviour. Compilation is not deployment.

The Pabbly half is no longer mocked: the live test above exercised the real
webhook, the real filter and the real Gmail step, and §7's sender question is
settled by Gmail's own response headers.

**Still unverified, and only deployment will settle it:** live Supabase
`generateLink` responses, real token expiry and reuse behaviour, the cross-device
callback against a real link, the deployed rate limiter under real traffic,
whether `x-forwarded-for` yields a usable client IP on this project (§9), and
whether the test messages actually landed in the inbox.

---

## 12. What is not done yet

| Item | Status | Who |
|---|---|---|
| Pabbly workflow created and configured | **Done** — verified field by field (§5) | — |
| Shared secret aligned with Supabase | **Done** — copied from the live filter into `.env` | — |
| Shared-secret rejection tested | **Done** — blocked at the filter, Gmail never ran (§11) | — |
| Gmail alias sends as `info@rev22.com.sg` | **Done** — confirmed by Gmail's own response headers (§7) | — |
| Inbox check on the test messages (both addresses) | Outstanding | You — §11 |
| Signup details validated server-side (`Stanley Aung`, `+6585777325`) | **Done** — accepted by the real validator | — |
| Migration applied | Not run | You — §10 step 1 |
| Secrets set + functions deployed | Not run | `scripts/auth-email/deploy.sh` after `npx supabase login` |
| `/reset-password` redirect URL added | Not changed — production Auth setting | You — §8 |
| Frontend deployed | Not run, and deliberately last | You |
| End-to-end test with a real token | Blocked on deployment | After §10 |
| January 2027 sender decision | Open — not urgent, not blocking | You — §7 |

### Why the last few need you

Deploying needs a Supabase access token: the CLI is not installed here and has
never been logged in, and I do not handle credentials. `npx supabase login` opens
a browser, stores the token, and `scripts/auth-email/deploy.sh` does the rest
without printing a single secret value.

## 13. Failure and retry behaviour

| Situation | Response | What happened |
|---|---|---|
| Pabbly returns 2xx | `200 {status:"submitted"}` | Pabbly has the request. **Not** proof an email arrived. |
| Pabbly returns non-2xx | `200 {status:"not_sent"}` | Nothing sent. The account, if created, is intact. The page offers Resend. |
| Pabbly does not answer in 10s | `200 {status:"submitted"}` | Unknown. It may already have sent. **Never auto-retried** — a duplicate verification email is worse than a slow one. |
| Signup created, delivery failed | `200 {status:"not_sent"}` | User preserved. No second account, no password rewrite. Recover via resend. |
| Rate limited | `429` + `Retry-After` | Nothing generated, nothing sent. |
| Limiter unavailable | `503` | Fails closed. |
| Secrets missing | `503 {error:"not_configured", missing:[names]}` | Names only, never values. |
| Notification fails after a password change | `200 {password_changed:true, notified:false}` | **The password did change.** The failure is recorded, not reported as a failed change. |

`request_id` is sent as an `Idempotency-Key`; Pabbly can deduplicate on it where
supported. That is not exactly-once delivery and is not claimed to be.

Every outcome is recorded in `public.auth_email_deliveries`, separately from
whether the request was admitted:

```sql
select action, outcome, count(*)
  from public.auth_email_deliveries
 where created_at > now() - interval '1 day'
 group by 1, 2 order by 1, 2;
```

---

## 14. Troubleshooting

| Symptom | Where to look |
|---|---|
| **"We could not reach the server"** on the signup/recovery form, with a **404 on the preflight** in the Network tab | The function is not deployed. Check with the one-liner below. This is not a code fault and not a connection fault — the browser hides the difference, which is why the message is vague. A dev build appends a hint saying exactly this. |
| Same message, but the preflight returns **204 without `Access-Control-Allow-Origin`** | The calling origin is not allowlisted. Add it to `AUTH_EMAIL_TEST_ORIGINS` and redeploy. `http://localhost:3000` is already there. |
| `503 not_configured` | The `missing` array names the secrets to set. |
| Everything returns 429 | `select * from public.auth_email_limits;` — check thresholds; `auth_email_rate_events` for the buckets. |
| Emails accepted but never arrive | Pabbly task history. A 2xx at the webhook only means Pabbly took it; look at whether the Gmail step ran. |
| Nothing reaches Pabbly | Filter step — a wrong `delivery_secret` stops the workflow by design. |
| Link lands on the wrong page | The redirect URL is not on Supabase's allowlist (§8), so Auth fell back to the Site URL. |
| Wrong sender address | §7. Check the alias, then whether Pabbly's Gmail action can set `From`. |
| **Mail lands in Junk, or never arrives at Outlook/Yahoo** | §7a. Run `npm run check:deliverability`. Almost always missing SPF/DKIM/DMARC on the sending domain, not the message. |
| `ip_seen: false` in logs | §9 — adjust `AUTH_EMAIL_TRUSTED_PROXY_HOPS`. Email limits still apply meanwhile. |

### Is it even deployed?

```bash
URL=$(grep '^VITE_SUPABASE_URL' .env | cut -d= -f2-)
for fn in auth-signup-request auth-resend-verification auth-request-recovery auth-change-password; do
  printf "  %-28s %s\n" "$fn" \
    "$(curl -s -o /dev/null -w '%{http_code}' -X OPTIONS "$URL/functions/v1/$fn" \
        -H 'Origin: http://localhost:3000' -H 'Access-Control-Request-Method: POST')"
done
```

`404` means not deployed. `204` means deployed and the origin is allowed. `204`
with no `Access-Control-Allow-Origin` in the response headers means deployed but
the origin is not allowlisted.

Function logs are structured JSON on one line, e.g.

```json
{"event":"auth_email.delivery","action":"signup","request_id":"…","outcome":"accepted","http_status":200,"ip_seen":true}
```

There is deliberately no email address, link or token in any log line — a test
asserts it.

---

## 15. Rollback

There is **no legacy Auth email hook** in this project, and none was invented.
Rolling back means pointing the application back at Supabase's default sender.

Rollback is a **frontend** change. Redeploy the previous frontend, and Supabase's
built-in sender resumes immediately — the Edge Functions become unreachable dead
weight rather than a second sending path. Do **not** leave both paths live: two
verification emails for one signup is worse than either path alone.

Specifically, revert:

* `src/pages/AffiliateJoinPage.tsx` → `supabase.auth.signUp`
* `src/pages/AffiliateForgotPasswordPage.tsx` → `supabase.auth.resetPasswordForEmail`
* `src/pages/AffiliateResetPasswordPage.tsx`, `src/pages/AffiliateAccountPage.tsx` → `supabase.auth.updateUser({password})`
* `src/App.tsx` → drop the two staff routes; `src/pages/LoginPage.tsx` → drop the link
* Delete `src/lib/authEmail.ts` and `src/lib/auth-email/`

Then optionally, in this order:

1. Leave the Edge Functions deployed but unreferenced (harmless), or
   `supabase functions delete auth-signup-request` and the other three.
2. Leave migration 200 in place. It touches nothing else and costs nothing.
   To remove it: `drop table public.auth_email_deliveries, public.auth_email_rate_events, public.auth_email_limits;`
   plus `drop function` for the four `auth_email_*` functions.
3. Remove the secrets last.

Note what rollback costs: staff lose password recovery entirely (it did not exist
before this work), and password-changed notifications stop.

---

## 16. What this does and does not change

It changes **who carries Auth email**. It does not lift Supabase's Auth limits.

Still in force: Supabase's own per-hour email caps and rate limits, its token
expiry, its password policy, and its account rules.

Newly in force, and this is the tightest constraint in the whole system:

* **100 emails per day.** Pabbly's Gmail action states this limit on the step
  itself ("You can send only 100 email/day as per Gmail API"). That is far lower
  than a personal Gmail account's usual send ceiling and it applies to every Auth
  email together — signups, resends, recoveries and change notifications.
* **Pabbly tasks.** Only the Gmail step is billable; the trigger and the filter
  are free. At the time of writing: 10,000 allotted, ~9,500 remaining.
* Gmail's spam and reputation handling, which no configuration overrides.

**Plan around the 100/day figure.** A roadshow that produces more than about 80
signups in a day will hit it, and the failures will look like delivery problems
rather than a quota. The rate limits in §4 do not protect you here — they cap one
person's requests, not the daily total. If volume grows, that ceiling is the
first thing to raise, and raising it means Google Workspace rather than a
configuration change.
