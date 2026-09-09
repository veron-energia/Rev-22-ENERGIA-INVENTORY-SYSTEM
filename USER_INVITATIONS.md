# Internal user invitations, and the sender change

Migrations 230–231, Edge Functions `admin-invite-user` and
`auth-accept-invitation`, `src/components/users/`, `src/pages/AcceptInvitationPage.tsx`.

Nothing here is committed, pushed, deployed, or applied to production data.

---

## 1. What replaced the manual procedure

The **Add User** button opened instructions to create an Auth user in the
Supabase dashboard and paste an `insert into public.profiles` into the SQL
editor. That is gone. **Invite User** opens a form; the invited person receives
an email, sets their own password, and only then gains access.

The administrator never sets, sees, or receives the password. There isn't one
until the recipient chooses it.

---

## 2. A privilege-escalation hole this had to close first

The invitation form enforces who may create which role. That would be worth
nothing on its own, because the **existing edit form writes the role directly**:

```ts
supabase.from('profiles').update({ role, is_active, ... })
```

so the only thing between a Manager and an Owner account is row-level security.
Both policy sets in this repository leave a way through:

| Policy | Hole |
|---|---|
| `02_rls_policies.sql` — `for all using (is_owner_or_manager())` | a **Manager may set any role on anyone**, including themselves |
| `00_complete_setup.sql` — `using (id = auth.uid() or is_owner_or_admin())` | **any signed-in user may update their own row**, role included |

So "Managers must not grant Owner, Admin, or Manager privileges" was not true
before this change. Migration 231 closes it with a **trigger**, not another
policy, because a trigger runs on every path into the table — the edit form, a
direct PostgREST call, a future function, an SQL editor session under a user's
JWT — and which policy happens to be installed stops mattering.

The database suite demonstrates the hole before closing it: with the trigger
disabled inside a transaction that is rolled back, a Manager promotes a Staff
member to Owner successfully.

Only `role` and `is_active` are guarded. Editing a name, a phone or an email is
untouched.

---

## 3. Permission matrix

| Acting role | May invite | May assign stores | May edit role/activation of |
|---|---|---|---|
| Owner | Owner, Admin, Manager, Inventory Manager, Staff | any store | anyone but themselves |
| Admin | Owner, Admin, Manager, Inventory Manager, Staff | any store | anyone but themselves |
| Manager | Inventory Manager, Staff | **only stores they are assigned to** | Inventory Managers and Staff only |
| Inventory Manager, Staff | nothing | — | nobody |

**Nobody changes their own role or activation**, whatever their role. An Owner
who needs to step down asks another Owner; that is a smaller inconvenience than
a self-service route to Owner existing at all.

Authority comes from `user_admin_role()`, which reads the caller's **current**
profile row and returns a role only when it is one that may administer users. A
role in a request body, a JWT claim, a stale client profile or a hidden button
is never consulted, and an administrator who has been deactivated is nobody.

---

## 4. Invitation lifecycle

```
administrator submits the form
  → invite_user_begin()      permissions, fields, conflicts — before any account exists
  → generateLink('invite')   creates the Auth account, returns a link, sends nothing
  → invite_user_provisioned() profile written INACTIVE and 'pending', stores attached
  → Pabbly → Gmail           the branded invitation email
  → recipient opens the link, Supabase gives them a session
  → auth-accept-invitation   Supabase sets the password, and only then:
  → invite_user_accept()     profile activated with the role the administrator chose
```

`generateLink({ type: 'invite' })` is used rather than `inviteUserByEmail`,
which would send through Supabase's own sender and bypass the Pabbly pipeline,
the branded template and the configured From address entirely.

### A pending user has no access

Two separate columns, deliberately not one flag: `is_active = false` **and**
`invitation_status = 'pending'`. Access requires an accepted invitation *and* an
active profile, so a single mistaken update cannot switch one on.

### Failure and retry

These systems are not one transaction, and the code does not pretend they are.
The durable invitation row plus a caller-supplied **request id** is what makes
the sequence resumable and a retry idempotent.

| What fails | What happens | What the administrator does |
|---|---|---|
| Permission or validation | nothing created anywhere | correct and resubmit |
| Address already in use | reported; **no password reset, no role change, no metadata replaced** | use the existing account |
| Link generation | invitation saved, no account | **Resend** |
| Profile write | account exists with no usable profile — grants nothing | **Resend** |
| Email delivery | account and invitation both exist | **Resend** |
| Double-click / retry | the same request id returns the first invitation | nothing |

**No account is ever deleted to recover from a failed email.**

A Pabbly acknowledgement is not proof of inbox delivery, and the wording says
so everywhere: the status is *accepted by the provider*, never *sent*. Where the
outcome is genuinely unknown (a timeout), the page says that instead of
guessing.

---

## 5. Acceptance callback

* Redirect: `PUBLIC_APP_URL` + `/accept-invitation`, chosen **by the server**
  from `CALLBACK_PATHS`. No client-supplied callback is accepted; a test origin
  is used only when it exactly matches a configured one.
* **Supabase → Authentication → URL Configuration** must list
  `https://<your-app>/accept-invitation` as a redirect URL, alongside the
  existing `/reset-password` and affiliate callbacks.
* The page handles the real Supabase session format, the same way
  `ResetPasswordPage` already does, and waits for the session before calling a
  link stale.
* Signed in as somebody else: the page says so and offers to sign out, rather
  than quietly replacing the session.
* Invalid, expired, used, cancelled and wrong-account all have their own
  message.

---

## 6. Resend and cancel

**Resend** reuses the same person and invitation. It never deletes and recreates
an account, and never touches a password. Rate limited to one attempt every two
minutes and ten in total. Resending for an **already-accepted** user is refused
with a pointer to Forgot Password — an invitation is not a password-reset
shortcut.

For an account that already exists, a fresh `invite` link is refused by
Supabase, so the resend falls back to regenerating a signup link — the path this
codebase already uses for an unconfirmed account, which leaves the password
untouched because there is none.

**Cancel** requires confirmation, records who and when, and marks the profile
`cancelled` and inactive.

### The limitation, stated plainly

**A link already in someone's inbox cannot be revoked at the provider.** Supabase
does not expose per-link revocation. A cancelled invitation's link can still
produce an Auth session.

That session gains nothing: `invite_user_accept()` refuses a cancelled
invitation, and the profile stays inactive with `invitation_status = 'cancelled'`.
Enforcement is at the application and database authorization level, not at the
link. There is a test for exactly this — accept with a valid session after
cancellation, and confirm the account is still inactive.

---

## 7. Sender: `info@rev22.com.sg`

### Where the sender actually comes from

| Path | Sender | Reply-To |
|---|---|---|
| Auth emails (signup, recovery, password changed, **invitations**) | `AUTH_EMAIL_FROM_ADDRESS` + `AUTH_EMAIL_FROM_NAME` | `AUTH_EMAIL_REPLY_TO` |
| Invoice emails (Resend) | `INVOICE_FROM` | **`INVOICE_REPLY_TO`** — added by this change; falls back to `INVOICE_FROM`, so an unconfigured project behaves exactly as before |

No template hardcodes an address. The "contact us" line in the password-changed
email already renders `config.replyTo`, so it moves with the configuration —
there is a test asserting no template names the old address.

`stanley@rev22.com.sg` appears nowhere in the code. It appears in
`PABBLY_GENERATELINK_AUTH_SETUP.md`, which already documents it as stale, and it
has deliberately **not** been globally replaced: it may legitimately identify an
account, a recipient or a historical record.

### The part an environment variable cannot do

**Setting `AUTH_EMAIL_FROM_ADDRESS` does not authorize Gmail to send as that
address.** The Pabbly Gmail action sends as an identity chosen from a dropdown
on the connected account. If `info@rev22.com.sg` is not a verified *Send mail
as* identity on that Gmail account, Gmail will either reject the send or
silently rewrite the From header to the connected address — which is worse,
because the payload will look correct while the delivered mail is not.

Required, in this order:

1. In the Gmail account Pabbly is connected to: **Settings → Accounts and
   Import → Send mail as → Add another email address**, add
   `info@rev22.com.sg`, and complete the verification email.
2. In Pabbly, on the Gmail action step, re-select the **Sender Email Address**
   as `info@rev22.com.sg`. This is chosen from a dropdown, not mapped from the
   payload, so it does not change when the application's configuration does.
3. Set the Supabase Function secrets:
   ```
   AUTH_EMAIL_FROM_ADDRESS=info@rev22.com.sg
   AUTH_EMAIL_FROM_NAME=Rev 22 Global Energia
   AUTH_EMAIL_REPLY_TO=info@rev22.com.sg
   INVOICE_FROM=Rev 22 Global Energia <info@rev22.com.sg>
   INVOICE_REPLY_TO=info@rev22.com.sg
   ```
4. Check SPF/DKIM/DMARC still align for the new address before relying on it.

All four move together or the sender is inconsistent between systems. **None of
this has been done** — this task stops at tested code and documentation.

---

## 8. Migrations and deployment order

1. `supabase/230_user_invitations.sql`
2. `supabase/231_profile_role_change_guard.sql`
3. `supabase functions deploy admin-invite-user`
4. `supabase functions deploy auth-accept-invitation`
5. Add `https://<your-app>/accept-invitation` to Supabase's redirect URLs.
6. Set the Function secrets in §7, after the Gmail alias is verified.
7. **Then** deploy the frontend.

Order matters twice over: the page calls functions migration 230 creates, and
the invitation form is useless until the Edge Functions exist. Deploying the
frontend first shows errors where the form should be.

Existing accounts and roles are untouched: `invitation_status` is added as a
nullable column, and a null means "created before invitations existed", which
every function treats as accepted.

### Rollback

```sql
-- 231: the privilege guard. Removing it reopens the escalation described in §2.
drop trigger if exists guard_profile_privileges on public.profiles;
drop function if exists public.trg_guard_profile_privileges();
drop function if exists public.profile_privilege_change_allowed();

-- 230: the invitation workflow. Do this only with the frontend rolled back too.
drop function if exists public.user_admin_list();
drop function if exists public.user_admin_orphan_invitations();
drop function if exists public.invite_user_begin(text,text,text,user_role,text,text,text,uuid[]);
drop function if exists public.invite_user_provisioned(uuid,uuid);
drop function if exists public.invite_user_record_delivery(uuid,text,text,boolean);
drop function if exists public.invite_user_accept(uuid,text);
drop function if exists public.invite_user_prepare_resend(uuid);
drop function if exists public.invite_user_cancel(uuid,text);
drop function if exists public.assignable_store_ids();
drop function if exists public.can_assign_role(user_role);
drop function if exists public.assignable_roles();
drop function if exists public.user_admin_role();
```

Keep `public.user_invitations` and `profiles.invitation_status`: dropping them
destroys the record of who was invited and by whom, and the column is additive.

**Recovery.** Every invitation is a row with its delivery outcome, and every
creation, acceptance and cancellation is in `audit_logs`:

```sql
select i.email, i.role, i.status, i.invited_at, i.last_email_status, p.full_name as invited_by
  from public.user_invitations i
  left join public.profiles p on p.id = i.invited_by
 order by i.invited_at desc;
```

An invitation whose account was never created shows in
`user_admin_orphan_invitations()` and can be resent.

---

## 9. Tests

| Suite | Result |
|---|---|
| `npm run test:users:db` | 60 checks passed |
| `npm run test:auth-email:edge` | 103 passed (18 new for invitations, 4 for the sender) |
| `deno check` on all six functions | clean |
| typecheck, build | clean |
| Existing suites (auth-email 17, therapy 19 + 76 db, tiktok 33 + 35 db, xero 8, survey 26, phones 9) | unchanged |

Covered: every role an Owner may create; a Manager creating Staff and Inventory
Managers and being refused Owner/Admin/Manager and unauthorized stores;
unauthenticated, Staff and **deactivated-Owner** callers refused; the edit-path
escalation demonstrated and then blocked in five directions; contact rules
matching the existing edit form; existing staff and affiliate addresses refused
without mutation; the same request id returning the first invitation; a pending
user having no access and not being a user administrator; acceptance activating
the intended role; a second acceptance refused; **cancellation refusing a valid
session from a previously issued link**; resend rate limiting and its ceiling;
resend refused for an accepted user; audit records; and the list leaking no
link, token or password.

Interface behaviour was checked by rendering the real components at **320, 375,
390 and 430 CSS px**: no horizontal overflow, no tap target under 36px, and
field-level errors marking `aria-invalid` on the field they belong to.

### Not verified

* **No end-to-end invitation has been sent.** That needs the migrations applied,
  both functions deployed, and the redirect URL configured — none of which this
  task does. The email payload and template are verified offline; the delivered
  message is not.
* **The Gmail Send-As identity for `info@rev22.com.sg` has not been checked.**
  Until it is, the From header that actually arrives is unknown, and it may be
  silently rewritten to the connected account. §7 has the steps.
* Real `From`/`Reply-To` headers as received have not been inspected.
* Supabase link expiry is a project setting; the email says a link is single-use
  and can be resent rather than naming a lifetime that may not match.
* The concurrency test covers a repeated request id, not two simultaneous
  requests racing inside the database. The unique index on a pending address is
  what makes that safe, and it is asserted; the race itself is not staged.
