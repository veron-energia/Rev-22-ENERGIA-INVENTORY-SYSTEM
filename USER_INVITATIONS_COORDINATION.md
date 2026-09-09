# User invitations — coordination note for agent one

Nothing is committed, pushed or deployed. Agent one's five modified files are
untouched.

## Migration numbers

**230 and 231.** Clear of 170–184 (invoices) and 200–226 (auth email, TikTok,
therapy).

## Files I own

| Path | Note |
|---|---|
| `supabase/230_user_invitations.sql`, `231_profile_role_change_guard.sql` | new |
| `supabase/functions/admin-invite-user/`, `auth-accept-invitation/` | new |
| `supabase/functions/_shared/auth-email/invitations.ts` | new |
| `src/lib/userInvitations.ts`, `src/components/users/*` | new |
| `src/pages/AcceptInvitationPage.tsx` | new |
| `scripts/users/**`, `vite.users-preview.config.mts` | new — tests and a preview harness |
| `USER_INVITATIONS.md` | new |

## Shared files I changed

| File | My change | Overlap |
|---|---|---|
| `src/pages/UsersPage.tsx` | replaced the manual instructions; list now shows invitation state | **None** — clean in the working tree |
| `src/App.tsx` | one route: `/accept-invitation` | one import, one line |
| `supabase/functions/_shared/auth-email/{admin,redirects,templates,pabbly}.ts` | additive: an invite link generator, one callback path, one template, one action type | no existing behaviour changed |
| `supabase/functions/send-invoice-email/index.ts` | **see below** | invoice-adjacent |
| `package.json` | one script: `test:users:db` | scripts block only |
| `.claude/launch.json` | one preview entry | additive |

## Two things to look at

**1. `send-invoice-email` now sets a Reply-To.** Three lines: it reads a new
`INVOICE_REPLY_TO` secret and passes `reply_to` to Resend, falling back to
`INVOICE_FROM` when unset — so a project that sets nothing behaves exactly as it
does today. The brief asked for the sender change to reach invoice email where
it is configurable, and this is the smallest way to do that. **If you would
rather own this file, say so and I will revert my three lines** and hand you the
change.

The rollout also wants `INVOICE_FROM` to become
`Rev 22 Global Energia <info@rev22.com.sg>`. That is a Supabase secret, not code,
and it is documented rather than done.

**2. `GeneratedLink` gained an optional `userId`.** Only the invitation path
reads it. Every existing caller is unaffected, and it is optional precisely so
the recovery and signup paths did not need touching.

## What I did NOT change

* No qualification, invoice, therapy or TikTok logic.
* No existing RLS policy. The privilege fix is a trigger, so no policy you may
  be relying on has moved.
* No existing role or account. `invitation_status` is nullable and a null means
  "predates invitations", which every function treats as accepted.
* No delivery mechanism. Auth email still goes through Pabbly; invoice email
  still goes through Resend.

## One thing worth knowing regardless of this task

The Users & Roles edit form writes `role` straight to `profiles`, and the
installed RLS lets a Manager set any role on anyone — or any user set their own.
Migration 231 closes that with a trigger. If any invoice or approval code
updates `profiles.role` or `profiles.is_active` directly, it will now be checked
against the same matrix. Server-side functions that legitimately need to can
declare it with `set_config('energia.profile_privilege_change', 'on', true)`
inside their transaction; the invitation functions do exactly that. **Tell me if
anything in your scope updates those two columns** and I will make sure it still
works.
