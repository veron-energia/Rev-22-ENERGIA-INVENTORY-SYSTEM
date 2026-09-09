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
  fromAddress: 'info@rev22.com.sg',
  fromName: 'Rev 22 Global Energia',
  replyTo: 'info@rev22.com.sg',
  allowedOrigins: ['https://energia.test'],
} as unknown as AuthEmailConfig;

const LINK = 'https://project.supabase.co/auth/v1/verify?token=abc&type=invite';
const REDIRECT = 'https://energia.test/accept-invitation';

const INPUT: InviteInput = {
  requestId: 'req-0000000001',
  email: 'new.person@energia.test',
  fullName: 'New Person',
  role: 'staff',
  workPhone: '+6591110000',
  personalPhone: '+6591110001',
  personalEmail: 'new.person@example.test',
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

Deno.test('a resend for an account that already exists falls back to regenerating', async () => {
  let usedFallback = false;
  const d = deps({
    generateInviteLink: () => Promise.resolve({ status: 'already_confirmed' as const }),
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
  assertEquals((good as { value: InviteInput }).value.email, 'new.person@energia.test');
});

Deno.test('the login email is normalized and never copied from the personal one', () => {
  const r = validateInvite({ ...INPUT, email: '  New.Person@Energia.TEST  ', personalEmail: 'other@example.test' });
  assert(r.ok);
  assertEquals(r.value.email, 'new.person@energia.test');
  assertEquals(r.value.personalEmail, 'other@example.test');

  const blank = validateInvite({ ...INPUT, personalEmail: '' });
  assert(blank.ok);
  assertEquals(blank.value.personalEmail, null, 'a blank personal email became the login email');
});
