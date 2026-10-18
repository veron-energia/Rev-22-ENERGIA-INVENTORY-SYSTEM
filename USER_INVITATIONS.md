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
  than quietly replacing the session. Since 429 the page tells the two apart
  by how the session signed in, not by the login's details: a session opened
  from an emailed link (the invitation, or the recovery link a confirmed login
  gets) may be the invitee's own; a password sign-in gets the warning. The
  page then asks the server (`{ check: true }`, nothing is set) whether the
  login has a pending invitation, and shows the form only if it has. A login
  with none (a member of staff or an affiliate who opened a reset link,
  however long ago), or with a used one, is told so and sent to sign in or
  reset the password. A cancelled or unfinished invitation, or one sent to
  another address, gets the server's words and "Go to sign in" only: that
  login is closed, so a reset link would not help. A removed member of staff
  invited again has an old, confirmed login that was never marked as
  invited, so the old check showed them only the warning, and their
  single-use link was then spent.
* `auth-accept-invitation` (429) accepts only a session opened from an
  emailed link. A removed member of staff invited again still has their old
  password, and the block on their login is lifted when the invitation is set
  up; that password alone must not switch them back on without the email. It
  answers 401 "Open the invitation link from your email to finish setting
  up." before anything is set.
* It then refuses, before any password is set, a login with no pending
  invitation (open, not cancelled, not used), sent to another address, or
  whose profile is not the pending one the invitation made. Before this, a
  login with no invitation went on to set a new password without the current
  one, from any old reset session: all staff, and any affiliate who used a
  reset link. That got round the 30-minute rule in `auth-change-password`.
  If the invitation cannot be checked, nothing is set. The decisions are in
  `_shared/auth-email/accept.ts`, with their tests in `tests/accept.test.ts`.
* 30 minutes, like reset links (the Owner, 18 Oct 2026; before, an
  invitation link worked at any age). With a pending invitation, the
  password is set only in the 30 minutes after the link was opened: the
  window of `auth-change-password`, from the same code (`invitationLinkState`
  in `_shared/auth-email/password.ts`), by the server's clock. A link opened
  longer ago is answered 403 `not_activated`, reason `link_expired`, "This
  invitation link has expired. Ask for a new invitation.", both to the
  page's `{ check: true }` and to a password, and nothing is set. The page
  shows those words and "Go to sign in", on arrival or when the password is
  sent. An Owner or Manager then presses **Resend** on Users & Roles, which
  sends a new link (section 6). This is checked after the pending invitation,
  so a login with no pending invitation, or a cancelled, used, expired,
  wrong-address or unfinished one, is still told that first.
* Invalid, expired, used, cancelled and wrong-account all have their own
  message.

---

## 6. Resend and cancel

**Resend** reuses the same person and invitation. It never deletes and recreates
an account, and never touches a password. Rate limited to one attempt every two
minutes and ten in total. Resending for an **already-accepted** user is refused
with a pointer to Forgot Password — an invitation is not a password-reset
shortcut.

For an account whose address is not confirmed yet, a fresh `invite` link is
made for the same login. Once the address is confirmed (the first link was
opened, perhaps by an email scanner) Supabase refuses `invite` and a signup
link alike, so since 429 the resend sends a **recovery** link for that same
login; it leaves the password untouched because there is none. An invitation
whose login or profile was never made is set up first (429), so its link
never reaches an account with no profile.

**Cancel** requires confirmation, records who and when, and marks the profile
`cancelled`, inactive and removed (a deleted date, 429), so Users & Roles no
longer lists it and the login stays blocked (412). The same address can be
invited again: the old login is reused, its profile is put back as the new
invitation's (pending, its stores only) and the block is lifted so the new
link works (`invite_user_reusable_login`, `invite_user_provisioned`).

A **removed member of staff** (a removed profile that is not a pending or
cancelled invitee's) may be invited again with their old email (the Owner,
10 Oct 2026). The invitation reuses their login, so everything they did before
stays linked to them. When it is set up, what their profile was (name, role,
state, removed date, stores) is kept in the audit log
(`user_invitation_login_reused`), the profile becomes the new invitation's
(pending, its role and stores only), and 412 lifts the block it placed, so the
new link works. Accepting switches them on. It is still their profile, so only
someone allowed to manage the role they had may invite them back: a Manager
may invite back Inventory Managers and Staff, not a Manager or an Owner
(`invite_user_begin` answers `forbidden`, scope `removed_staff`, and saves
nothing). That holds whatever the removed profile's invitation state: after
an Owner invites back a removed Manager and then cancels, a Manager still may
not invite them; nor a cancelled invitee an Owner had invited as a Manager. A member of staff who is only switched off, not removed, is switched
on again on Users & Roles; their address stays in use.

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

### 429 (9 Oct 2026)

1. `supabase/429_users_invitations_and_payment_methods.sql`
2. `supabase functions deploy auth-accept-invitation` (it carries
   `_shared/auth-email/accept.ts`, `password.ts` and `validate.ts`)
3. `supabase functions deploy admin-invite-user` (it carries
   `_shared/auth-email/invitations.ts`, `password.ts` and `validate.ts`)
4. `supabase functions deploy auth-change-password` (it carries
   `_shared/auth-email/change.ts`, `password.ts` and `validate.ts`)
5. **Then** deploy the frontend.

Deploy each function by its name, as above. Never run a bare
`supabase functions deploy`: it would also deploy folders that are not part of
429.

The new `admin-invite-user` asks `invite_user_reusable_login`, which 429 makes,
so the migration goes first.

`auth-accept-invitation` now accepts only a session opened from an emailed
link (§5). Deploy it no later than `admin-invite-user`: the new
`admin-invite-user` invites removed staff again, which lifts the block on their
login, and their old password must not be enough to accept. A new invitee has
no password, so nothing changes for them. The new Accept page asks the new
`auth-accept-invitation` first (`{ check: true }`; the old one refuses that
body), so deploy the function before the front end. It shows the form only to
a login with a pending invitation; the live one shows a removed member of staff
invited again only "You are signed in as ...", so ship the front end soon after
`admin-invite-user`. `auth-change-password` now asks for the current password
unless the session came from an email link in the last 30 minutes (the Owner
confirmed 30 minutes on 10 Oct 2026); a link opened longer ago is told so, and
the reset pages offer "Request a new link" beside the Current Password field.
The current password, when given, also goes to Supabase Auth with the change
(`current_password`). Deploy it before, or with, the front end: the old one
refuses the `current_password` field the new pages send.

### What the 30-minute rule does not stop

The 30-minute rule is in `auth-change-password`, and for invitation links in
`auth-accept-invitation` (18 Oct 2026). Supabase Auth itself
does not know it, and no Supabase setting enforces 30 minutes. Someone at a
signed-in device who uses the browser's developer tools can still set a
password through Supabase Auth directly from a session opened by an email link.
The app keeps its session in the browser, so a shared device that is left
signed in is still open to this. The rule makes the pages safe; it does not
close the gap on its own.

* **Supabase → Authentication → "Require current password when updating"**
  (`GOTRUE_SECURITY_UPDATE_PASSWORD_REQUIRE_CURRENT_PASSWORD`) closes the
  direct route for **password sign-ins**: Supabase then refuses their change
  without the current password. Sessions opened by an email link are exempt,
  at any age. Test it on a local Supabase Auth first, then switch it on in
  production. `auth-change-password` sends the current password along, so it
  keeps working with this on. Whether it is on in production was not checked
  (it cannot be read with SQL).
* Do **not** switch on **"Secure password change"** unless the pages are
  changed first. It refuses a session over 24 hours old even with the current
  password, and asks for a code the pages cannot ask for. It also does not
  enforce 30 minutes.
* What stays open: an email-link session, straight to Supabase Auth. With
  neither setting on, at any age; with "Secure password change", up to 24
  hours. Closing it needs a decision from the Owner, such as signing out
  email-link sessions once the password is set, or a shorter session time or
  an inactivity time-out in Supabase Auth.
* Accepting an invitation cannot be done this way. Switching a login on is
  `invite_user_accept`, which only the service role may call. Going straight
  to Supabase Auth only sets a password, which is the same gap as above.

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
`user_admin_orphan_invitations()`, which Users & Roles lists (429) with Resend
and Cancel.

---

## 9. Tests

| Suite | Result |
|---|---|
| `npm run test:users:db` | 60 checks passed |
| `npm run test:auth-email:edge` | 103 passed (18 new for invitations, 4 for the sender) |
| `npm run test:auth-email:edge` (429) | 158 passed, including `tests/accept.test.ts` (auth-accept-invitation's decisions and its two reads) and `tests/change.test.ts` (auth-change-password's decisions: every refusal changes nothing) |
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
