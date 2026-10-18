// Inviting an internal user: the decisions, without a Supabase project.
//
// The cases here are the ones that are impractical to stage live — a link that
// generates but an email that fails, a profile write that fails after the
// account exists, a second click arriving on a request that is already done.

import { assert, assertEquals, assertStringIncludes } from 'jsr:@std/assert@1';
import {
  cancelInvitation, createInvitation, resendInvitation, validateInvite,
  type InvitationDeps, type InviteInput,
} from '../invitations.ts';
import type { AuthEmailConfig } from '../config.ts';
import type { DeliveryResult } from '../pabbly.ts';

const CONFIG = {
  supabaseUrl: 'https://project.supabase.co',
  publicApiKey: 'anon',
  serviceRoleKey: 'service',
  publicAppUrl: 'https://energia.test',
  callbackBaseUrls: ['https://energia.test'],
  fromAddress: 'info@example.com',
  fromName: 'Rev 22 Global Energia',
  replyTo: 'info@example.com',
  allowedOrigins: ['https://energia.test'],
} as unknown as AuthEmailConfig;

const LINK = 'https://project.supabase.co/auth/v1/verify?token=abc&type=invite';
const RECOVERY_LINK = 'https://project.supabase.co/auth/v1/verify?token=def&type=recovery';
const REDIRECT = 'https://energia.test/accept-invitation';

const INPUT: InviteInput = {
  requestId: 'req-0000000001',
  email: 'new.person@example.com',
  fullName: 'New Person',
  role: 'staff',
  workPhone: '+61491579455',
  personalPhone: '+61491579760',
  personalEmail: 'new.person.home@example.com',
  storeIds: [],
};

const accepted: DeliveryResult = { outcome: 'accepted', httpStatus: 200, detail: 'ok' };
const rejected: DeliveryResult = { outcome: 'provider_rejected', httpStatus: 400, detail: 'bad hook' };
const unknown: DeliveryResult = { outcome: 'timeout', httpStatus: null, detail: 'timed out' };

function deps(overrides: Partial<InvitationDeps> & {
  begin?: Record<string, unknown>;
  prepare?: Record<string, unknown>;
  delivery?: DeliveryResult;
} = {}): InvitationDeps & { calls: string[]; delivered: { to: string; html: string; text: string }[] } {
  const calls: string[] = [];
  const delivered: { to: string; html: string; text: string }[] = [];
  const base: InvitationDeps = {
    callerRpc: (fn, _args) => {
      calls.push(`caller:${fn}`);
      if (fn === 'invite_user_begin') {
        return Promise.resolve({ data: overrides.begin ?? { outcome: 'created', invitation_id: 'inv-1' }, error: null });
      }
      if (fn === 'invite_user_prepare_resend') {
        return Promise.resolve({
          data: overrides.prepare ?? { outcome: 'ok', invitation_id: 'inv-1', email: INPUT.email, full_name: INPUT.fullName },
          error: null,
        });
      }
      if (fn === 'invite_user_cancel') return Promise.resolve({ data: { outcome: 'cancelled' }, error: null });
      return Promise.resolve({ data: null, error: null });
    },
    adminRpc: (fn, _args) => {
      calls.push(`admin:${fn}`);
      return Promise.resolve({ data: { outcome: 'provisioned' }, error: null });
    },
    generateInviteLink: () => Promise.resolve({
      status: 'ok' as const,
      link: { actionLink: LINK, email: INPUT.email, displayName: INPUT.fullName, userId: 'auth-1' },
    }),
    regenerateSignupLink: () => Promise.resolve({
      status: 'ok' as const,
      link: { actionLink: LINK, email: INPUT.email, displayName: INPUT.fullName, userId: 'auth-1' },
    }),
    generateRecoveryLink: () => Promise.resolve({
      status: 'ok' as const,
      link: { actionLink: RECOVERY_LINK, email: INPUT.email, displayName: INPUT.fullName, userId: 'auth-1' },
    }),
    deliver: (_c, req) => {
      delivered.push({ to: req.to, html: req.html, text: req.text });
      return Promise.resolve(overrides.delivery ?? accepted);
    },
    admin: {},
  };
  return { ...base, ...overrides, calls, delivered } as never;
}

Deno.test('a created invitation never returns the link', async () => {
  const d = deps();
  const result = await createInvitation(d, CONFIG, INPUT, REDIRECT, 'Olivia Owner');
  assertEquals(result.kind, 'created');
  const serialized = JSON.stringify(result);
  assert(!serialized.includes('token='), 'the response carried a token');
  assert(!serialized.includes(LINK), 'the response carried the action link');
});

Deno.test('the link goes into the email and the email is addressed to the invitee', async () => {
  const d = deps();
  await createInvitation(d, CONFIG, INPUT, REDIRECT, 'Olivia Owner');
  assertEquals(d.delivered.length, 1);
  assertEquals(d.delivered[0].to, INPUT.email);
  // The HTML escapes the ampersand, as HTML must; the plain-text part carries
  // the link verbatim so it survives copy and paste.
  assertStringIncludes(d.delivered[0].html, LINK.replace(/&/g, '&amp;'));
  assertStringIncludes(d.delivered[0].text, LINK);
  assert(!d.delivered[0].html.includes('&amp;amp;'), 'the link was escaped twice');
  assertStringIncludes(d.delivered[0].html, 'Set Up My Account');
  assertStringIncludes(d.delivered[0].html, 'Olivia Owner');
});

Deno.test('the invitation email carries no password or temporary credential', async () => {
  const d = deps();
  await createInvitation(d, CONFIG, INPUT, REDIRECT);
  const body = `${d.delivered[0].html}\n${d.delivered[0].text}`.toLowerCase();
  assert(!/temporary password|password is|one-time code|passcode/.test(body), body.slice(0, 200));
  assertStringIncludes(body, 'choose your own password');
});

Deno.test('a permission refusal never reaches the account-creating step', async () => {
  const d = deps({ begin: { outcome: 'forbidden', message: 'Your role may not create owner accounts.' } });
  const result = await createInvitation(d, CONFIG, { ...INPUT, role: 'owner' }, REDIRECT);
  assertEquals(result.kind, 'forbidden');
  assert(!d.calls.some(c => c.startsWith('admin:')), 'the server-only functions ran anyway');
  assertEquals(d.delivered.length, 0);
});

Deno.test('an address already in use is reported and nothing is created', async () => {
  const d = deps({ begin: { outcome: 'email_in_use', scope: 'affiliate', message: 'That address already belongs to an affiliate account.' } });
  const result = await createInvitation(d, CONFIG, INPUT, REDIRECT);
  assertEquals(result.kind, 'email_in_use');
  assertEquals(d.delivered.length, 0);
});

Deno.test('a second click on the same request returns the first invitation', async () => {
  const d = deps({ begin: { outcome: 'existing_request', invitation_id: 'inv-1', message: 'Already recorded.' } });
  const result = await createInvitation(d, CONFIG, INPUT, REDIRECT);
  assertEquals(result.kind, 'existing_request');
  assertEquals(d.delivered.length, 0, 'a duplicate submission sent a second email');
});

Deno.test('a pending invitation for the address is pointed at, not duplicated', async () => {
  const d = deps({ begin: { outcome: 'existing_pending', invitation_id: 'inv-9', message: 'Already pending.' } });
  const result = await createInvitation(d, CONFIG, INPUT, REDIRECT);
  assertEquals(result.kind, 'existing_pending');
});

Deno.test('a link that cannot be generated leaves the invitation to be resent', async () => {
  const d = deps({
    generateInviteLink: () => Promise.resolve({ status: 'error' as const, message: 'upstream down' }),
  });
  const result = await createInvitation(d, CONFIG, INPUT, REDIRECT);
  assertEquals(result.kind, 'provisioning_failed');
  assertStringIncludes((result as { message: string }).message, 'Resend');
  assert(d.calls.includes('admin:invite_user_record_delivery'), 'the failure was not recorded');
  assert(!d.calls.includes('admin:invite_user_provisioned'));
});

Deno.test('a link from somewhere other than this project is refused', async () => {
  const d = deps({
    generateInviteLink: () => Promise.resolve({
      status: 'ok' as const,
      link: { actionLink: 'https://evil.test/verify?token=x', email: INPUT.email, displayName: 'x', userId: 'auth-1' },
    }),
  });
  const result = await createInvitation(d, CONFIG, INPUT, REDIRECT);
  assertEquals(result.kind, 'provisioning_failed');
  assertEquals(d.delivered.length, 0, 'an untrusted link was emailed');
});

Deno.test('a profile that cannot be written leaves no usable account', async () => {
  const d = deps({
    adminRpc: (fn) => fn === 'invite_user_provisioned'
      ? Promise.resolve({ data: null, error: { message: 'store missing' } })
      : Promise.resolve({ data: {}, error: null }),
  });
  const result = await createInvitation(d, CONFIG, INPUT, REDIRECT);
  assertEquals(result.kind, 'provisioning_failed');
  assertStringIncludes((result as { message: string }).message, 'no access has been granted');
  assertEquals(d.delivered.length, 0);
});

// 413: cancelled between invite_user_begin and invite_user_provisioned.
Deno.test('an invitation cancelled while its login is being made sends no email', async () => {
  const d = deps({
    adminRpc: (fn) => {
      d.calls.push(`admin:${fn}`);
      return Promise.resolve(fn === 'invite_user_provisioned'
        ? { data: { outcome: 'cancelled', message: 'This invitation is no longer pending.' }, error: null }
        : { data: null, error: null });
    },
  });
  const result = await createInvitation(d, CONFIG, INPUT, REDIRECT, 'Olivia Owner');
  assertEquals(result.kind, 'provisioning_failed');
  assertEquals((result as { invitationId?: string }).invitationId, 'inv-1');
  assertStringIncludes((result as { message: string }).message, 'cancelled while it was being set up');
  assertStringIncludes((result as { message: string }).message, 'No email was sent');
  assertEquals(d.delivered.length, 0, 'the email went out for a cancelled invitation');
  assert(!d.calls.includes('admin:invite_user_record_delivery'), 'a delivery was recorded for an email never sent');
});

Deno.test('any answer but "provisioned" sends no email', async () => {
  for (const data of [{ outcome: 'accepted' }, {}, null]) {
    const d = deps({
      adminRpc: (fn) => Promise.resolve(fn === 'invite_user_provisioned' ? { data, error: null } : { data: null, error: null }),
    });
    const result = await createInvitation(d, CONFIG, INPUT, REDIRECT);
    assertEquals(result.kind, 'provisioning_failed', JSON.stringify(data));
    assertEquals(d.delivered.length, 0, JSON.stringify(data));
  }
});

Deno.test('a resend cancelled while its new link is being made sends no email', async () => {
  let asked = 0;
  const d = deps({
    callerRpc: (fn) => {
      d.calls.push(`caller:${fn}`);
      if (fn !== 'invite_user_prepare_resend') return Promise.resolve({ data: null, error: null });
      asked++;
      return Promise.resolve({
        data: asked === 1
          ? { outcome: 'ok', invitation_id: 'inv-1', email: INPUT.email, full_name: INPUT.fullName }
          : { outcome: 'not_pending', status: 'cancelled', message: 'This invitation was cancelled. Create a new one if they still need access.' },
        error: null,
      });
    },
  });
  const result = await resendInvitation(d, CONFIG, 'inv-1', REDIRECT, 'req-2');
  assertEquals(result.kind, 'provisioning_failed');
  assertStringIncludes((result as { message: string }).message, 'was cancelled');
  assertStringIncludes((result as { message: string }).message, 'No email was sent');
  assertEquals(asked, 2, 'the invitation was not asked about again just before sending');
  assertEquals(d.delivered.length, 0, 'the email went out for a cancelled invitation');
});

Deno.test('a resend asks again as the caller just before sending, and still sends when nothing changed', async () => {
  const d = deps();
  const result = await resendInvitation(d, CONFIG, 'inv-1', REDIRECT, 'req-2');
  assertEquals(result.kind, 'created');
  assertEquals(d.calls.filter(c => c === 'caller:invite_user_prepare_resend').length, 2);
  assert(!d.calls.includes('admin:invite_user_prepare_resend'), 'the second look bypassed the caller');
  assertEquals(d.delivered.length, 1);
});

Deno.test('a rejected email is reported as not sent, and the account still exists', async () => {
  const d = deps({ delivery: rejected });
  const result = await createInvitation(d, CONFIG, INPUT, REDIRECT);
  assertEquals(result.kind, 'created');
  assertEquals((result as { delivery: string }).delivery, 'failed');
  assertStringIncludes((result as { detail: string }).detail, 'not sent');
});

Deno.test('an email whose outcome is unknown is not described as failed', async () => {
  const d = deps({ delivery: unknown });
  const result = await createInvitation(d, CONFIG, INPUT, REDIRECT);
  assertStringIncludes((result as { detail: string }).detail, 'not certain');
});

Deno.test('a rate-limited resend does not send and says when to retry', async () => {
  const d = deps({ prepare: { outcome: 'rate_limited', message: 'Wait a moment.', retry_after_seconds: 90 } });
  const result = await resendInvitation(d, CONFIG, 'inv-1', REDIRECT, 'req-2');
  assertEquals(result.kind, 'rate_limited');
  assertEquals((result as { retryAfterSeconds: number }).retryAfterSeconds, 90);
  assertEquals(d.delivered.length, 0);
});

Deno.test('resending an accepted invitation is refused rather than becoming a password reset', async () => {
  const d = deps({ prepare: { outcome: 'not_pending', status: 'accepted', message: 'Ask them to use Forgot Password.' } });
  const result = await resendInvitation(d, CONFIG, 'inv-1', REDIRECT, 'req-2');
  assertEquals(result.kind, 'provisioning_failed');
  assertEquals(d.delivered.length, 0);
});

Deno.test('a resend whose invite link fails outright still falls back to regenerating', async () => {
  let usedFallback = false;
  const d = deps({
    prepare: { outcome: 'ok', invitation_id: 'inv-1', email: INPUT.email, full_name: INPUT.fullName, auth_user_id: 'auth-1' },
    generateInviteLink: () => Promise.resolve({ status: 'error' as const, message: 'upstream' }),
    regenerateSignupLink: () => {
      usedFallback = true;
      return Promise.resolve({
        status: 'ok' as const,
        link: { actionLink: LINK, email: INPUT.email, displayName: INPUT.fullName, userId: 'auth-1' },
      });
    },
  });
  const result = await resendInvitation(d, CONFIG, 'inv-1', REDIRECT, 'req-2');
  assertEquals(result.kind, 'created');
  assert(usedFallback, 'the fallback path was not used');
  assertEquals(d.delivered.length, 1);
});

// 429 (ADMIN-AUTH-7 e): once the first link was opened, even by an email
// scanner, the login's address is confirmed and Supabase refuses an 'invite'
// link and a signup link. A recovery link for that same login works.
Deno.test('a resend for a login whose address is confirmed sends a recovery link for that login', async () => {
  let signupTried = false;
  const d = deps({
    prepare: { outcome: 'ok', invitation_id: 'inv-1', email: INPUT.email, full_name: INPUT.fullName, auth_user_id: 'auth-1' },
    generateInviteLink: () => Promise.resolve({ status: 'already_confirmed' as const }),
    regenerateSignupLink: () => { signupTried = true; return Promise.resolve({ status: 'already_confirmed' as const }); },
  });
  const result = await resendInvitation(d, CONFIG, 'inv-1', REDIRECT, 'req-2');
  assertEquals(result.kind, 'created');
  assert(!signupTried, 'a signup link was tried for a confirmed address');
  assertEquals(d.delivered.length, 1);
  assertStringIncludes(d.delivered[0].text, RECOVERY_LINK);
  assert(!d.calls.includes('admin:invite_user_provisioned'), 'a login already tied was set up again');
});

// 429 (ADMIN-AUTH-7 c): an invitation whose set-up never finished has no
// login tied to it. Before 429 a resend sent the link with no profile behind
// it, and accepting would have marked the invitation accepted with no access.
Deno.test('a resend of an unfinished invitation sets up the login it makes before sending', async () => {
  const order: string[] = [];
  const d = deps({
    adminRpc: (fn, args) => {
      order.push(`admin:${fn}`);
      if (fn === 'invite_user_reusable_login') return Promise.resolve({ data: null, error: null });
      if (fn === 'invite_user_provisioned') {
        assertEquals(args.p_auth_user_id, 'auth-1', 'the login the link was made for');
        return Promise.resolve({ data: { outcome: 'provisioned' }, error: null });
      }
      return Promise.resolve({ data: null, error: null });
    },
    deliver: (_c, req) => { order.push('deliver'); d.delivered.push({ to: req.to, html: req.html, text: req.text }); return Promise.resolve(accepted); },
  });
  const result = await resendInvitation(d, CONFIG, 'inv-1', REDIRECT, 'req-2');
  assertEquals(result.kind, 'created');
  assert(order.indexOf('admin:invite_user_provisioned') >= 0, 'the login was never set up');
  assert(order.indexOf('admin:invite_user_provisioned') < order.indexOf('deliver'), 'the email went before the set-up');
});

Deno.test('a resend of an unfinished invitation whose set-up is refused sends nothing', async () => {
  const d = deps({
    adminRpc: (fn) => Promise.resolve(fn === 'invite_user_provisioned'
      ? { data: { outcome: 'login_in_use', message: 'x' }, error: null }
      : { data: null, error: null }),
  });
  const result = await resendInvitation(d, CONFIG, 'inv-1', REDIRECT, 'req-2');
  assertEquals(result.kind, 'provisioning_failed');
  assertStringIncludes((result as { message: string }).message, 'cannot be invited');
  assertEquals(d.delivered.length, 0);
});

// 429 (ADMIN-AUTH-7 d): a cancelled person invited again. Their login is set
// up first (profile pending again, 412's block lifted), then the link.
Deno.test('inviting a cancelled person again reuses their login: set up first, then the link', async () => {
  const order: string[] = [];
  const d = deps({
    adminRpc: (fn, args) => {
      order.push(`admin:${fn}`);
      if (fn === 'invite_user_reusable_login') return Promise.resolve({ data: 'auth-old', error: null });
      if (fn === 'invite_user_provisioned') {
        assertEquals(args.p_auth_user_id, 'auth-old');
        return Promise.resolve({ data: { outcome: 'provisioned' }, error: null });
      }
      return Promise.resolve({ data: null, error: null });
    },
    generateInviteLink: () => { order.push('invite-link'); return Promise.resolve({
      status: 'ok' as const, link: { actionLink: LINK, email: INPUT.email, displayName: '', userId: 'auth-old' } }); },
  });
  const result = await createInvitation(d, CONFIG, INPUT, REDIRECT, 'Olivia Owner');
  assertEquals(result.kind, 'created');
  assert(order.indexOf('admin:invite_user_provisioned') < order.indexOf('invite-link'),
    'the link was made before the old login was unblocked');
  assertEquals(order.filter(c => c === 'admin:invite_user_provisioned').length, 1, 'set up twice');
  assertEquals(d.delivered.length, 1);
});

Deno.test('inviting a cancelled person again whose address is confirmed sends a recovery link', async () => {
  const d = deps({
    adminRpc: (fn) => Promise.resolve(fn === 'invite_user_reusable_login'
      ? { data: 'auth-1', error: null }
      : { data: { outcome: 'provisioned' }, error: null }),
    generateInviteLink: () => Promise.resolve({ status: 'already_confirmed' as const }),
  });
  const result = await createInvitation(d, CONFIG, INPUT, REDIRECT);
  assertEquals(result.kind, 'created');
  assertStringIncludes(d.delivered[0].text, RECOVERY_LINK);
});

// The Owner, 10 Oct 2026: a removed member of staff may be invited again with
// their old email; their login is reused, so their history stays linked.
Deno.test('inviting a removed member of staff again reuses their login and sends a recovery link for it', async () => {
  const order: string[] = [];
  const d = deps({
    adminRpc: (fn, args) => {
      order.push(`admin:${fn}`);
      if (fn === 'invite_user_reusable_login') return Promise.resolve({ data: 'auth-removed', error: null });
      if (fn === 'invite_user_provisioned') {
        assertEquals(args.p_auth_user_id, 'auth-removed');
        return Promise.resolve({ data: { outcome: 'provisioned' }, error: null });
      }
      return Promise.resolve({ data: null, error: null });
    },
    // Their address was confirmed long ago, so Supabase Auth refuses 'invite'.
    generateInviteLink: () => { order.push('invite-link'); return Promise.resolve({ status: 'already_confirmed' as const }); },
    generateRecoveryLink: () => { order.push('recovery-link'); return Promise.resolve({
      status: 'ok' as const, link: { actionLink: RECOVERY_LINK, email: INPUT.email, displayName: '', userId: 'auth-removed' } }); },
  });
  const result = await createInvitation(d, CONFIG, INPUT, REDIRECT, 'Olivia Owner');
  assertEquals(result.kind, 'created');
  assert(order.indexOf('admin:invite_user_provisioned') < order.indexOf('recovery-link'),
    'the link was made before their login was set up and unblocked');
  assertEquals(order.filter(c => c === 'admin:invite_user_provisioned').length, 1, 'set up twice');
  assertEquals(d.delivered.length, 1);
  assertStringIncludes(d.delivered[0].text, RECOVERY_LINK);
});

Deno.test('a removed member of staff whose old role the inviter may not manage is refused before anything runs', async () => {
  const message = 'This person was removed from Users & Roles, or their invitation was cancelled. '
    + 'Your role may not manage the role they have. Ask an Owner to invite them again. Nothing has been changed.';
  const d = deps({ begin: { outcome: 'forbidden', scope: 'removed_staff', message } });
  const result = await createInvitation(d, CONFIG, INPUT, REDIRECT);
  assertEquals(result.kind, 'forbidden');
  assertEquals(result.kind === 'forbidden' ? result.message : '', message);
  assert(!d.calls.some(c => c.startsWith('admin:')), 'the server-only functions ran anyway');
  assertEquals(d.delivered.length, 0);
});

Deno.test('a link made for a different login than the one set up is never sent', async () => {
  const d = deps({
    adminRpc: (fn) => Promise.resolve(fn === 'invite_user_reusable_login'
      ? { data: 'auth-old', error: null }
      : { data: { outcome: 'provisioned' }, error: null }),
  });
  const result = await createInvitation(d, CONFIG, INPUT, REDIRECT);
  assertEquals(result.kind, 'provisioning_failed');
  assertEquals(d.delivered.length, 0);
});

// ADMIN-AUTH-7 (c): the old wording said "Nothing was changed" after the
// invitation had been saved.
Deno.test('an address whose login is someone else\'s is refused without "nothing was changed"', async () => {
  let recovery = false;
  const d = deps({
    adminRpc: (fn) => { d.calls.push(`admin:${fn}`); return Promise.resolve({ data: null, error: null }); },
    generateInviteLink: () => Promise.resolve({ status: 'already_confirmed' as const }),
    generateRecoveryLink: () => { recovery = true; return Promise.resolve({ status: 'no_such_user' as const }); },
  });
  const result = await createInvitation(d, CONFIG, INPUT, REDIRECT);
  assertEquals(result.kind, 'provisioning_failed');
  const message = (result as { message: string }).message;
  assert(!/nothing was changed/i.test(message), message);
  assertStringIncludes(message, 'The invitation is saved');
  assertStringIncludes(message, 'cancel it');
  assert(!recovery, 'a recovery link was made for a login that is not this invitation\'s');
  assert(!d.calls.includes('admin:invite_user_provisioned'));
  assert(d.calls.includes('admin:invite_user_record_delivery'), 'the failure was not recorded');
  assertEquals(d.delivered.length, 0);
});

Deno.test('a failed login check saves the invitation and sends nothing', async () => {
  const d = deps({
    adminRpc: (fn) => Promise.resolve(fn === 'invite_user_reusable_login'
      ? { data: null, error: { message: 'function does not exist' } }
      : { data: null, error: null }),
  });
  const result = await createInvitation(d, CONFIG, INPUT, REDIRECT);
  assertEquals(result.kind, 'provisioning_failed');
  assertStringIncludes((result as { message: string }).message, 'Resend');
  assertEquals(d.delivered.length, 0);
});

Deno.test('cancelling passes through the caller, so the database decides', async () => {
  const d = deps();
  const result = await cancelInvitation(d, 'inv-1', 'hired someone else');
  assertEquals(result.kind, 'cancelled');
  assert(d.calls.includes('caller:invite_user_cancel'));
  assert(!d.calls.some(c => c === 'admin:invite_user_cancel'), 'cancel bypassed the caller check');
});

Deno.test('validation rejects what the interface should never send', () => {
  const bad: [Partial<InviteInput>, string][] = [
    [{ ...INPUT, requestId: 'x' }, 'request_id'],
    [{ ...INPUT, fullName: '   ' }, 'full_name'],
    [{ ...INPUT, email: 'not-an-email' }, 'email'],
    [{ ...INPUT, role: 'superuser' as never }, 'role'],
    [{ ...INPUT, personalEmail: 'nope' }, 'personal_email'],
    [{ ...INPUT, storeIds: ['not-a-uuid'] }, 'store_ids'],
  ];
  for (const [input, field] of bad) {
    const r = validateInvite(input);
    assert(!r.ok, `${field} was accepted`);
    assertEquals((r as { field: string }).field, field);
  }
  const good = validateInvite(INPUT);
  assert(good.ok);
  assertEquals((good as { value: InviteInput }).value.email, 'new.person@example.com');
});

Deno.test('the login email is normalized and never copied from the personal one', () => {
  const r = validateInvite({ ...INPUT, email: '  New.Person@Example.COM  ', personalEmail: 'other@example.com' });
  assert(r.ok);
  assertEquals(r.value.email, 'new.person@example.com');
  assertEquals(r.value.personalEmail, 'other@example.com');

  const blank = validateInvite({ ...INPUT, personalEmail: '' });
  assert(blank.ok);
  assertEquals(blank.value.personalEmail, null, 'a blank personal email became the login email');
});

// Accepting an invitation is tested in accept.test.ts (429).
