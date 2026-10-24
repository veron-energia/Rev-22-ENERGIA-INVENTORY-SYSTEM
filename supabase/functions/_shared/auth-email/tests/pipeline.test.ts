// End-to-end through the pipeline with every collaborator faked: the states that
// are hard to reproduce against a live project are the ones worth pinning down.

import { assert, assertEquals, assertFalse, assertNotEquals } from 'jsr:@std/assert@1';
import { EMAIL_IN_USE_MESSAGE, handlePublicRequest } from '../pipeline.ts';
import { affiliateExistsMessage, type ExistingAffiliate } from '../existing.ts';
import { recoveryEndpoint, resendEndpoint, signupEndpoint } from '../flows.ts';
import { MissingConfigError } from '../config.ts';
import {
  APP_URL, ACTION_LINK, MAGIC_LINK, allowAll, fakeAdmin, flowDeps, magicLink, okLink,
  postRequest, recordingDeliver, testConfig, validSignupBody,
} from './support.ts';

// deno-lint-ignore no-explicit-any
const run = (req: Request, endpoint: any, admin = fakeAdmin(allowAll), config = testConfig()) =>
  handlePublicRequest(req, endpoint, { loadConfig: () => config, makeAdmin: () => admin });

const bodyOf = async (response: Response) => await response.json();

// ---------------------------------------------------------------------------
// Signup (437: straight in; the Owner's decisions of 20 Oct 2026)
// ---------------------------------------------------------------------------

Deno.test('a new signup makes the login already confirmed, with the details, and sends nothing', async () => {
  const { sent, deliver } = recordingDeliver();
  const calls: string[] = [];
  const deps = flowDeps({
    deliver,
    affiliateSignupExisting: (_a, args) => {
      calls.push('existing');
      const { requestId, ...rest } = args;
      assertEquals(rest, { email: 'ada@example.com', phone: '+6591234567', name: 'Ada Lovelace' });
      assert(/^[0-9a-f-]{36}$/.test(requestId), 'the request id goes with it (its Audit Log row links to the delivery row)');
      return Promise.resolve({ matched: null, loginEmail: false, emailHint: null });
    },
    accountState: () => { calls.push('state'); return Promise.resolve('none'); },
    createConfirmedSignup: (_a, args) => {
      calls.push('create');
      assertEquals(args.email, 'ada@example.com');
      assertEquals(args.password, validSignupBody.password);
      assertEquals(args.metadata.first_name, 'Ada');
      assertEquals(args.metadata.last_name, 'Lovelace');
      assertEquals(args.metadata.phone, '+6591234567');
      assertEquals(args.metadata.role_hint, 'affiliate');
      assertEquals(args.metadata.signup_source, 'affiliate_join');
      return Promise.resolve({ status: 'created', userId: 'u-1' });
    },
  });

  const admin = fakeAdmin(allowAll);
  const response = await run(postRequest(validSignupBody), signupEndpoint(deps), admin);
  assertEquals(response.status, 200);
  const body = await bodyOf(response);
  assertEquals(body.ok, true);
  assertEquals(body.status, 'created');
  assertEquals(calls, ['existing', 'state', 'create']);
  assertEquals(sent.length, 0, 'no email at sign-up: the email is verified later, from the Account page');
  const outcomes = admin.calls.filter(c => c.fn === 'auth_email_record_outcome').map(c => [c.args.p_outcome, c.args.p_detail]);
  assertEquals(outcomes, [['requested', null], ['suppressed', 'account_created']]);
});

Deno.test('an address that already has a login is told so, and nothing about that login changes', async () => {
  for (const state of ['confirmed', 'unconfirmed'] as const) {
    const { sent, deliver } = recordingDeliver();
    let created = 0;
    let regenerated = 0;
    const deps = flowDeps({
      deliver,
      accountState: () => Promise.resolve(state),
      createConfirmedSignup: () => { created += 1; return Promise.resolve({ status: 'created', userId: 'u-2' }); },
      regenerateSignupLink: () => { regenerated += 1; return Promise.resolve(okLink()); },
    });
    const response = await run(postRequest({ ...validSignupBody, password: 'a-completely-different-password' }), signupEndpoint(deps));
    assertEquals(response.status, 409, state);
    const body = await bodyOf(response);
    assertEquals(body.error, 'email_in_use');
    assertEquals(body.message, EMAIL_IN_USE_MESSAGE);
    assert(/sign in/i.test(body.message) && /reset your password/i.test(body.message), 'it offers Sign in and Reset password');
    assertEquals(created, 0, 'no second login');
    assertEquals(regenerated, 0, 'and no email');
    assertEquals(sent.length, 0);
  }
});

Deno.test('two presses at once: the second finds the first login and is told the email is in use', async () => {
  const deps = flowDeps({ createConfirmedSignup: () => Promise.resolve({ status: 'exists' }) });
  const response = await run(postRequest(validSignupBody), signupEndpoint(deps));
  assertEquals(response.status, 409);
  assertEquals((await bodyOf(response)).error, 'email_in_use');
});

Deno.test('a password Supabase refuses is a field error, with its own words', async () => {
  const deps = flowDeps({
    createConfirmedSignup: () => Promise.resolve({ status: 'refused', field: 'password', message: 'Password is known to be weak' }),
  });
  const response = await run(postRequest(validSignupBody), signupEndpoint(deps));
  assertEquals(response.status, 400);
  const body = await bodyOf(response);
  assertEquals(body.error, 'invalid_request');
  assertEquals(body.fields, { password: 'Password is known to be weak' });
});

Deno.test('a login that could not be made is a failure, not a success', async () => {
  const admin = fakeAdmin(allowAll);
  const deps = flowDeps({ createConfirmedSignup: () => Promise.resolve({ status: 'error', message: 'database unavailable' }) });
  const response = await run(postRequest(validSignupBody), signupEndpoint(deps), admin);
  assertEquals(response.status, 503);
  assertFalse((await response.text()).includes('database unavailable'));
  assertEquals(admin.calls.filter(c => c.fn === 'auth_email_record_outcome').at(-1)?.args.p_outcome, 'failed');
});

// ---------------------------------------------------------------------------
// 466: an existing affiliate's email or phone is sent to Sign in (the Owner,
// 24 Oct 2026). Nothing is made; the database logs the try.
// ---------------------------------------------------------------------------

/** A sign-up whose lookup answers `existing`, counting what else it asked for. */
function existingDeps(existing: ExistingAffiliate, state: 'none' | 'confirmed' | 'unconfirmed' = 'none') {
  const seen = { states: 0, created: 0, sent: 0, lookups: [] as { email: string; phone: string; name: string }[], requestIds: [] as string[] };
  const deps = flowDeps({
    affiliateSignupExisting: (_a, { requestId, ...args }) => {
      seen.lookups.push(args); seen.requestIds.push(requestId); return Promise.resolve(existing);
    },
    accountState: () => { seen.states += 1; return Promise.resolve(state); },
    createConfirmedSignup: () => { seen.created += 1; return Promise.resolve({ status: 'created', userId: 'u-466' }); },
    deliver: () => { seen.sent += 1; return Promise.resolve({ outcome: 'accepted', httpStatus: 200, detail: '' }); },
  });
  return { deps, seen };
}

Deno.test('466: an existing affiliate\'s phone (another email typed): 409 affiliate_exists with the masked login email, and nothing is made', async () => {
  const { deps, seen } = existingDeps({ matched: 'phone', loginEmail: false, emailHint: 's•••@rev22.com.sg' });
  const admin = fakeAdmin(allowAll);
  const response = await run(postRequest({ ...validSignupBody, email: 'Someone.New@Example.com' }), signupEndpoint(deps), admin);
  assertEquals(response.status, 409);
  const body = await bodyOf(response);
  assertEquals(body.error, 'affiliate_exists');
  assertEquals(body.matched, 'phone');
  assertEquals(body.email_hint, 's•••@rev22.com.sg');
  assertEquals(body.message, affiliateExistsMessage('phone', 's•••@rev22.com.sg'));
  assert(/phone number already has an Energia affiliate account/.test(body.message) && body.message.includes('s•••@rev22.com.sg'));
  assert(typeof body.request_id === 'string');
  assertEquals(Object.keys(body).sort(), ['email_hint', 'error', 'matched', 'message', 'request_id']);
  assertEquals(seen.lookups, [{ email: 'someone.new@example.com', phone: '+6591234567', name: 'Ada Lovelace' }],
    'the email, phone and name as validated');
  assertEquals(seen.requestIds, [body.request_id], 'the database gets this request\'s id, for its Audit Log row');
  assertEquals(seen.states, 1, 'the email typed is checked as a login first (it is none here)');
  assertEquals(seen.created, 0, 'no login');
  assertEquals(seen.sent, 0, 'no email');
  const outcomes = admin.calls.filter(c => c.fn === 'auth_email_record_outcome').map(c => [c.args.p_outcome, c.args.p_detail]);
  assertEquals(outcomes, [['requested', null], ['suppressed', 'affiliate_exists:phone']]);
});

Deno.test('466: a phone several affiliates have: no hint, and words that say to use the email they used', async () => {
  const { deps, seen } = existingDeps({ matched: 'phone', loginEmail: false, emailHint: null });
  const response = await run(postRequest(validSignupBody), signupEndpoint(deps));
  assertEquals(response.status, 409);
  const body = await bodyOf(response);
  assertEquals(body.error, 'affiliate_exists');
  assertEquals(body.matched, 'phone');
  assertFalse('email_hint' in body, 'no hint at all');
  assertEquals(body.message, 'This phone number already has an Energia affiliate account. Sign in with the email you used for it, or reset your password if you have forgotten it.');
  assertEquals(seen.created, 0);
});

Deno.test('466: an affiliate\'s own login email: today\'s email_in_use, now with matched, and no login', async () => {
  const { deps, seen } = existingDeps({ matched: 'email', loginEmail: true, emailHint: null }, 'confirmed');
  const response = await run(postRequest(validSignupBody), signupEndpoint(deps));
  assertEquals(response.status, 409);
  const body = await bodyOf(response);
  assertEquals(body.error, 'email_in_use', 'the body 437\'s pages read');
  assertEquals(body.message, EMAIL_IN_USE_MESSAGE);
  assertEquals(body.matched, 'email');
  assertFalse('email_hint' in body);
  assertEquals(seen.states, 1, 'the login check is asked too, as for staff\'s email (the same work either way)');
  assertEquals(seen.created, 0);
});

Deno.test('466: another email of an affiliate (her record\'s, her sign-up\'s): affiliate_exists matched email, with the hint', async () => {
  const { deps, seen } = existingDeps({ matched: 'email', loginEmail: false, emailHint: 'a•••@example.com' });
  const admin = fakeAdmin(allowAll);
  const response = await run(postRequest(validSignupBody), signupEndpoint(deps), admin);
  assertEquals(response.status, 409);
  const body = await bodyOf(response);
  assertEquals(body.error, 'affiliate_exists');
  assertEquals(body.matched, 'email');
  assertEquals(body.email_hint, 'a•••@example.com');
  assertEquals(body.message, 'This email is already on an Energia affiliate account, which signs in with a•••@example.com. Sign in with that email, or reset your password if you have forgotten it.');
  assertEquals(seen.states, 1, 'asked together with the lookup; the affiliate\'s email is answered first');
  assertEquals(seen.created, 0);
  assertEquals(admin.calls.filter(c => c.fn === 'auth_email_record_outcome').at(-1)?.args.p_detail, 'affiliate_exists:email');
});

Deno.test('466: a login\'s email (staff, a sign-up never finished) with an affiliate\'s phone: email_in_use, as before', async () => {
  // The database answers nothing for such an email (it is no affiliate\'s, and
  // nothing of the affiliate is told); a fake that did answer the phone still
  // gets email_in_use, the email first.
  for (const existing of [
    { matched: null, loginEmail: false, emailHint: null },
    { matched: 'phone', loginEmail: false, emailHint: 's•••@example.com' },
  ] as ExistingAffiliate[]) {
    const { deps, seen } = existingDeps(existing, 'confirmed');
    const response = await run(postRequest(validSignupBody), signupEndpoint(deps));
    assertEquals(response.status, 409);
    const body = await bodyOf(response);
    assertEquals(body.error, 'email_in_use');
    assertFalse('email_hint' in body);
    assertEquals(seen.created, 0);
  }
});

Deno.test('466: an affiliate\'s login email and staff\'s get the same answer from the same work (both lookups, once each)', async () => {
  const answers: Record<string, unknown>[] = [];
  const asked: string[][] = [];
  for (const [existing, state] of [
    [{ matched: 'email', loginEmail: true, emailHint: null }, 'confirmed'],  // an affiliate's login email
    [{ matched: null, loginEmail: false, emailHint: null }, 'confirmed'],    // staff's (nothing of an affiliate)
  ] as [ExistingAffiliate, 'confirmed'][]) {
    const order: string[] = [];
    const deps = flowDeps({
      affiliateSignupExisting: () => { order.push('existing'); return Promise.resolve(existing); },
      accountState: () => { order.push('state'); return Promise.resolve(state); },
      createConfirmedSignup: () => { order.push('create'); return Promise.resolve({ status: 'created', userId: 'u' }); },
    });
    const admin = fakeAdmin(allowAll);
    const response = await run(postRequest(validSignupBody), signupEndpoint(deps), admin);
    assertEquals(response.status, 409);
    const body = await bodyOf(response);
    delete body.request_id;
    answers.push(body);
    asked.push([...order, ...admin.calls.map(c => c.fn)]);
  }
  assertEquals(answers[0], answers[1]);
  assertEquals(asked[0], asked[1]);
  assertEquals(asked[0].filter(x => x === 'existing' || x === 'state'), ['existing', 'state']);
});

Deno.test('466: the database\'s reply read through the live lookup: one that is not of the shape makes nothing (503)', async () => {
  const { affiliateSignupExisting } = await import('../admin.ts');
  for (const reply of [{}, { error: 'x' }, { matched: 'email', login_email: 'true', email_hint: null }, { matched: 'phone' }, null]) {
    let created = 0;
    const admin = fakeAdmin({ ...allowAll, affiliate_signup_existing: () => reply });
    const deps = flowDeps({
      affiliateSignupExisting,
      createConfirmedSignup: () => { created += 1; return Promise.resolve({ status: 'created', userId: 'u' }); },
    });
    const response = await run(postRequest(validSignupBody), signupEndpoint(deps), admin);
    assertEquals(response.status, 503, JSON.stringify(reply));
    assertEquals(created, 0, `fail closed: ${JSON.stringify(reply)}`);
    const call = admin.calls.find(c => c.fn === 'affiliate_signup_existing');
    assert(call && typeof call.args.p_request_id === 'string', 'the request id is passed');
  }
  // The replies the database gives are read as they are.
  const admin = fakeAdmin({ ...allowAll, affiliate_signup_existing: () => ({ matched: null, login_email: false, email_hint: null, affiliates: 0 }) });
  const response = await run(postRequest(validSignupBody), signupEndpoint(flowDeps({ affiliateSignupExisting })), admin);
  assertEquals(response.status, 200);
});

Deno.test('466: a login check that fails makes nothing (503), even for an affiliate\'s email', async () => {
  let created = 0;
  const deps = flowDeps({
    affiliateSignupExisting: () => Promise.resolve({ matched: 'email', loginEmail: false, emailHint: 'a•••@example.com' }),
    accountState: () => Promise.reject(new Error('account state lookup failed: down')),
    createConfirmedSignup: () => { created += 1; return Promise.resolve({ status: 'created', userId: 'u' }); },
  });
  const response = await run(postRequest(validSignupBody), signupEndpoint(deps));
  assertEquals(response.status, 503);
  assertEquals(created, 0);
});

Deno.test('466: a customer who is not an affiliate (no match) signs up as before', async () => {
  const { deps, seen } = existingDeps({ matched: null, loginEmail: false, emailHint: null });
  const response = await run(postRequest(validSignupBody), signupEndpoint(deps));
  assertEquals(response.status, 200);
  assertEquals((await bodyOf(response)).status, 'created');
  assertEquals(seen.created, 1);
});

Deno.test('466: the lookup gets the name typed as onboarding puts it together (a household phone is told apart by it)', async () => {
  // A family member on an affiliate's phone, with a record of her own and no
  // login, who types her record's name gets no match from the database and
  // signs up as before; the name must reach it as complete_affiliate_onboarding
  // reads it: first, a space, last; no stray spaces; the first name alone.
  for (const [first, last, name] of [
    ['  Jo   Ann ', ' Testhome ', 'Jo Ann Testhome'],
    ['Jo', '', 'Jo'],
  ]) {
    const { deps, seen } = existingDeps({ matched: null, loginEmail: false, emailHint: null });
    const response = await run(postRequest({ ...validSignupBody, first_name: first, last_name: last }), signupEndpoint(deps));
    assertEquals(response.status, 200);
    assertEquals(seen.lookups.map(l => l.name), [name]);
    assertEquals(seen.created, 1);
  }
});

Deno.test('466: a lookup that fails, or answers something unreadable, makes nothing (503)', async () => {
  for (const lookup of [
    () => Promise.reject(new Error('existing affiliate lookup failed: function public.affiliate_signup_existing does not exist')),
    () => Promise.reject(new Error('existing affiliate lookup returned an unexpected value')),
  ]) {
    let created = 0;
    const admin = fakeAdmin(allowAll);
    const deps = flowDeps({
      affiliateSignupExisting: lookup,
      createConfirmedSignup: () => { created += 1; return Promise.resolve({ status: 'created', userId: 'u' }); },
    });
    const response = await run(postRequest(validSignupBody), signupEndpoint(deps), admin);
    assertEquals(response.status, 503);
    assertFalse((await response.text()).includes('affiliate_signup_existing'));
    assertEquals(created, 0, 'fail closed: no second login');
    assertEquals(admin.calls.filter(c => c.fn === 'auth_email_record_outcome').at(-1)?.args.p_outcome, 'failed');
  }
});

Deno.test('466: every refusal costs a rate-limit slot, and a refused reservation never reaches the lookup', async () => {
  const order: string[] = [];
  const admin = fakeAdmin({
    auth_email_reserve: () => { order.push('reserve'); return { allowed: true, retry_after_seconds: 0 }; },
    auth_email_record_outcome: () => null,
  });
  const { deps } = existingDeps({ matched: 'phone', loginEmail: false, emailHint: null });
  const wrapped = { ...deps, affiliateSignupExisting: (a: unknown, args: { email: string; phone: string; name: string; requestId: string }) => { order.push('existing'); return deps.affiliateSignupExisting(a, args); } };
  await run(postRequest(validSignupBody), signupEndpoint(wrapped), admin);
  assertEquals(order, ['reserve', 'existing']);
  assertEquals(admin.calls.filter(c => c.fn === 'auth_email_reserve').length, 1, 'reserved once, never handed back');

  let looked = 0;
  const limited = fakeAdmin({
    auth_email_reserve: () => ({ allowed: false, retry_after_seconds: 600, scope: 'ip' }),
    auth_email_record_outcome: () => null,
  });
  const response = await run(postRequest(validSignupBody), signupEndpoint(flowDeps({
    affiliateSignupExisting: () => { looked += 1; return Promise.resolve({ matched: 'phone', loginEmail: false, emailHint: null }); },
  })), limited);
  assertEquals(response.status, 429);
  assertEquals(looked, 0, 'past the limit, nothing is looked up or logged');
});

Deno.test('466: the refusal never carries the login email itself, a secret or the password', async () => {
  const config = testConfig();
  const { deps } = existingDeps({ matched: 'phone', loginEmail: false, emailHint: 's•••@example.com' });
  const text = await (await run(postRequest(validSignupBody), signupEndpoint(deps), fakeAdmin(allowAll), config)).text();
  for (const secret of ['sam@example.com', config.serviceRoleKey, config.hashSecret, validSignupBody.password]) {
    assertFalse(text.includes(secret), `response leaked: ${secret.slice(0, 40)}`);
  }
});

// ---------------------------------------------------------------------------
// Resend, and the Account page's verification email (437)
// ---------------------------------------------------------------------------

Deno.test('resend sends the old sign-up link only to an account that exists and is unverified', async () => {
  for (const [state, expected] of [['none', 0], ['unconfirmed', 1]] as const) {
    const { sent, deliver } = recordingDeliver();
    let created = 0;
    const deps = flowDeps({
      deliver,
      accountState: () => Promise.resolve(state),
      createConfirmedSignup: () => { created += 1; return Promise.resolve({ status: 'created', userId: 'u' }); },
      // Note the arguments this path is even capable of passing: an email and
      // a redirect. No password, no metadata.
      regenerateSignupLink: (_a, args) => {
        assertEquals(Object.keys(args).sort(), ['email', 'redirectTo']);
        return Promise.resolve(okLink());
      },
    });
    const response = await run(postRequest({ email: 'ada@example.com' }), resendEndpoint(deps));
    assertEquals(response.status, 200, state);
    assertEquals(sent.length, expected, `state=${state}`);
    if (expected) assertEquals(sent[0].request.subject, 'Verify Your Energia Affiliate Account');
    assertEquals(created, 0, 'resend must never create an account');
  }
});

Deno.test('a confirmed affiliate whose email is not verified gets the verification email: a sign-in link to /affiliate/verify', async () => {
  const { sent, deliver } = recordingDeliver();
  const asked: string[] = [];
  const deps = flowDeps({
    deliver,
    accountState: () => Promise.resolve('confirmed'),
    affiliateEmailNeedsVerification: (_a, email) => { asked.push(email); return Promise.resolve(true); },
    generateMagicLink: (_a, args) => {
      assertEquals(args.email, 'ada@example.com');
      assertEquals(args.redirectTo, `${APP_URL}/affiliate/verify`);
      assertEquals(Object.keys(args).sort(), ['email', 'redirectTo']);
      return Promise.resolve(magicLink('ada@example.com', 'Ada Lovelace'));
    },
  });
  const response = await run(postRequest({ email: 'Ada@Example.com' }), resendEndpoint(deps));
  assertEquals(response.status, 200);
  assertEquals((await bodyOf(response)).status, 'submitted');
  assertEquals(asked, ['ada@example.com']);
  assertEquals(sent.length, 1);
  assertEquals(sent[0].request.to, 'ada@example.com');
  assertEquals(sent[0].request.subject, 'Verify Your Energia Email Address');
  assertEquals(sent[0].request.actionType, 'verify_signup');
  assertEquals(sent[0].request.recipientRole, 'affiliate');
  assert(sent[0].request.html.includes(MAGIC_LINK.replace(/&/g, '&amp;')), 'the link is in the email');
  assert(sent[0].request.text.includes(MAGIC_LINK));
});

Deno.test('a verified, a staff or a non-affiliate login is sent nothing', async () => {
  const { sent, deliver } = recordingDeliver();
  let links = 0;
  const deps = flowDeps({
    deliver,
    accountState: () => Promise.resolve('confirmed'),
    affiliateEmailNeedsVerification: () => Promise.resolve(false),
    generateMagicLink: () => { links += 1; return Promise.resolve(magicLink()); },
  });
  const response = await run(postRequest({ email: 'ada@example.com' }), resendEndpoint(deps));
  assertEquals(response.status, 200);
  assertEquals(links, 0);
  assertEquals(sent.length, 0);
});

Deno.test('resend answers identically whatever the address holds', async () => {
  const bodies = [];
  for (const [state, needs] of [['none', false], ['unconfirmed', false], ['confirmed', false], ['confirmed', true]] as const) {
    const response = await run(postRequest({ email: 'ada@example.com' }), resendEndpoint(flowDeps({
      accountState: () => Promise.resolve(state),
      affiliateEmailNeedsVerification: () => Promise.resolve(needs),
    })));
    assertEquals(response.status, 200);
    const body = await bodyOf(response);
    delete body.request_id;
    bodies.push(JSON.stringify(body));
  }
  assertEquals(new Set(bodies).size, 1, `bodies differed: ${bodies.join(' | ')}`);
});

Deno.test('a verification email that fails to send says so, so the page can offer a retry', async () => {
  const { deliver } = recordingDeliver({ outcome: 'provider_rejected', httpStatus: 400, detail: 'workflow disabled' });
  const response = await run(postRequest({ email: 'ada@example.com' }), resendEndpoint(flowDeps({
    deliver,
    accountState: () => Promise.resolve('confirmed'),
    affiliateEmailNeedsVerification: () => Promise.resolve(true),
  })));
  const body = await bodyOf(response);
  assertEquals(response.status, 200);
  assertEquals(body.status, 'not_sent');
});

Deno.test('an ambiguous timeout is not retried and is not reported as a failure', async () => {
  const { sent, deliver } = recordingDeliver({ outcome: 'timeout', httpStatus: null, detail: 'no response' });
  const admin = fakeAdmin(allowAll);
  const response = await run(postRequest({ email: 'ada@example.com' }), resendEndpoint(flowDeps({
    deliver, accountState: () => Promise.resolve('confirmed'), affiliateEmailNeedsVerification: () => Promise.resolve(true),
  })), admin);
  const body = await bodyOf(response);

  assertEquals(sent.length, 1, 'exactly one attempt: the message may already have gone');
  assertEquals(body.status, 'submitted', 'a timeout is not proof of failure');
  assertEquals(admin.calls.filter(c => c.fn === 'auth_email_record_outcome').at(-1)?.args.p_outcome, 'timeout');
});

// ---------------------------------------------------------------------------
// Recovery
// ---------------------------------------------------------------------------

Deno.test('recovery maps each flow to its own allowlisted callback', async () => {
  for (const [flow, path, role] of [
    ['affiliate', '/affiliate/reset-password', 'affiliate'],
    ['staff', '/reset-password', 'staff'],
  ] as const) {
    const { sent, deliver } = recordingDeliver();
    const deps = flowDeps({
      deliver,
      generateRecoveryLink: (_a, args) => {
        assertEquals(args.redirectTo, `${APP_URL}${path}`);
        return Promise.resolve(okLink('someone@example.com'));
      },
    });
    await run(postRequest({ email: 'someone@example.com', flow }), recoveryEndpoint(deps));
    assertEquals(sent[0].request.recipientRole, role);
    assertEquals(sent[0].request.actionType, 'password_recovery');
  }
});

Deno.test('recovery for an address with no account looks exactly like one that has', async () => {
  const missing = await run(postRequest({ email: 'nobody@example.com', flow: 'staff' }),
    recoveryEndpoint(flowDeps({ generateRecoveryLink: () => Promise.resolve({ status: 'no_such_user' }) })));
  const present = await run(postRequest({ email: 'someone@example.com', flow: 'staff' }), recoveryEndpoint(flowDeps()));

  assertEquals(missing.status, present.status);
  const a = await bodyOf(missing);
  const b = await bodyOf(present);
  delete a.request_id; delete b.request_id;
  assertEquals(a, b);
});

// ---------------------------------------------------------------------------
// What must never come back
// ---------------------------------------------------------------------------

Deno.test('no response ever carries the action link, a token, a secret or the password', async () => {
  const config = testConfig();
  for (const [endpoint, body] of [
    [signupEndpoint(flowDeps()), validSignupBody],
    [signupEndpoint(flowDeps({ accountState: () => Promise.resolve('confirmed') })), validSignupBody],
    [resendEndpoint(flowDeps({ accountState: () => Promise.resolve('unconfirmed') })), { email: 'ada@example.com' }],
    [resendEndpoint(flowDeps({ accountState: () => Promise.resolve('confirmed'), affiliateEmailNeedsVerification: () => Promise.resolve(true) })),
      { email: 'ada@example.com' }],
    [recoveryEndpoint(flowDeps()), { email: 'ada@example.com', flow: 'staff' }],
  ] as const) {
    const text = await (await run(postRequest(body), endpoint, fakeAdmin(allowAll), config)).text();
    for (const secret of [
      ACTION_LINK, MAGIC_LINK, 'abc123', 'mag456', '/auth/v1/verify', config.pabblySharedSecret,
      config.serviceRoleKey, config.hashSecret, config.pabblyWebhookUrl, validSignupBody.password,
    ]) {
      assertFalse(text.includes(secret), `response leaked: ${secret.slice(0, 40)}`);
    }
  }
});

Deno.test('a caller cannot choose the recipient, the content, the redirect or a role', async () => {
  const { sent, deliver } = recordingDeliver();
  let created = 0;
  const attempt = {
    ...validSignupBody,
    to: 'victim@example.com',
    subject: 'Free money',
    html: '<p>spam</p>',
    redirect_to: 'https://evil.example/steal',
    role: 'service_role',
    from_email: 'spoof@rev22.com.sg',
  };
  const response = await run(postRequest(attempt), signupEndpoint(flowDeps({
    deliver, createConfirmedSignup: () => { created += 1; return Promise.resolve({ status: 'created', userId: 'u' }); },
  })));

  assertEquals(response.status, 400, 'an unknown field is refused, not ignored');
  assertEquals((await bodyOf(response)).error, 'invalid_request');
  assertEquals(created, 0, 'no login is made while the shape is wrong');
  assertEquals(sent.length, 0, 'nothing is sent while the shape is wrong');
});

Deno.test('even a valid request cannot influence sender, subject or recipient of the verification email', async () => {
  const { sent, deliver } = recordingDeliver();
  const config = testConfig();
  await run(postRequest({ email: 'ada@example.com' }), resendEndpoint(flowDeps({
    deliver,
    accountState: () => Promise.resolve('confirmed'),
    affiliateEmailNeedsVerification: () => Promise.resolve(true),
    // Supabase reports the address it actually holds; that is what gets mailed.
    generateMagicLink: () => Promise.resolve(magicLink('ada@example.com')),
  })), fakeAdmin(allowAll), config);

  assertEquals(sent[0].request.to, 'ada@example.com');
  assertEquals(sent[0].request.subject, 'Verify Your Energia Email Address');
  assertEquals(sent[0].config.fromAddress, config.fromAddress);
  assertEquals(sent[0].config.fromName, config.fromName);
});

// ---------------------------------------------------------------------------
// Rate limiting and failure modes
// ---------------------------------------------------------------------------

Deno.test('a refused reservation stops before any login is made or anything sent', async () => {
  const { sent, deliver } = recordingDeliver();
  let created = 0;
  const admin = fakeAdmin({
    auth_email_reserve: () => ({ allowed: false, retry_after_seconds: 420, scope: 'email' }),
    auth_email_record_outcome: () => null,
  });
  const deps = flowDeps({ deliver, createConfirmedSignup: () => { created += 1; return Promise.resolve({ status: 'created', userId: 'u' }); } });

  const response = await run(postRequest(validSignupBody), signupEndpoint(deps), admin);
  const body = await bodyOf(response);

  assertEquals(response.status, 429);
  assertEquals(response.headers.get('Retry-After'), '420');
  assertEquals(body.error, 'rate_limited');
  assert(body.message.includes('7 minutes'), body.message);
  // Which bucket ran out is a fact about the account; it stays server-side.
  assertFalse(JSON.stringify(body).includes('email'));
  assertEquals(created, 0);
  assertEquals(sent.length, 0);
});

Deno.test('the reservation is claimed before the login is made, and never handed back', async () => {
  const order: string[] = [];
  const admin = fakeAdmin({
    auth_email_reserve: () => { order.push('reserve'); return { allowed: true, retry_after_seconds: 0 }; },
    auth_email_record_outcome: () => null,
  });
  const deps = flowDeps({
    affiliateSignupExisting: () => { order.push('existing'); return Promise.resolve({ matched: null, loginEmail: false, emailHint: null }); },
    accountState: () => { order.push('state'); return Promise.resolve('none'); },
    createConfirmedSignup: () => { order.push('create'); return Promise.resolve({ status: 'error', message: 'down' }); },
  });

  await run(postRequest(validSignupBody), signupEndpoint(deps), admin);
  assertEquals(order, ['reserve', 'existing', 'state', 'create']);
  // A failure does not refund the slot: that is what caps retries.
  assertEquals(admin.calls.filter(c => c.fn === 'auth_email_reserve').length, 1);
});

Deno.test('the reservation comes before the verification link too', async () => {
  const order: string[] = [];
  const admin = fakeAdmin({
    auth_email_reserve: () => { order.push('reserve'); return { allowed: true, retry_after_seconds: 0 }; },
    auth_email_record_outcome: () => null,
  });
  await run(postRequest({ email: 'ada@example.com' }), resendEndpoint(flowDeps({
    accountState: () => Promise.resolve('confirmed'),
    affiliateEmailNeedsVerification: () => { order.push('needs'); return Promise.resolve(true); },
    generateMagicLink: () => { order.push('link'); return Promise.resolve(magicLink()); },
    deliver: () => { order.push('deliver'); return Promise.resolve({ outcome: 'failed', httpStatus: null, detail: 'down' }); },
  })), admin);
  assertEquals(order, ['reserve', 'needs', 'link', 'deliver']);
});

Deno.test('a limiter that cannot answer fails closed', async () => {
  const { sent, deliver } = recordingDeliver();
  let created = 0;
  const admin = fakeAdmin({ auth_email_reserve: () => new Error('connection refused') });
  const response = await run(postRequest(validSignupBody), signupEndpoint(flowDeps({
    deliver, createConfirmedSignup: () => { created += 1; return Promise.resolve({ status: 'created', userId: 'u' }); },
  })), admin);

  assertEquals(response.status, 503);
  assertEquals(created, 0, 'no limiter means no sign-up, not unlimited sign-ups');
  assertEquals(sent.length, 0, 'no limiter means no sending, not unlimited sending');
  assertFalse((await response.text()).includes('connection refused'));
});

Deno.test('missing configuration reports names, never values — and the browser can read it', async () => {
  const saved = Deno.env.get('PUBLIC_APP_URL');
  Deno.env.set('PUBLIC_APP_URL', APP_URL);
  try {
    const response = await handlePublicRequest(postRequest(validSignupBody), signupEndpoint(flowDeps()), {
      loadConfig: () => { throw new MissingConfigError(['PABBLY_AUTH_EMAIL_SHARED_SECRET', 'AUTH_EMAIL_FROM_ADDRESS']); },
      makeAdmin: () => fakeAdmin(allowAll),
    });
    assertEquals(response.status, 503);
    const body = await bodyOf(response);
    assertEquals(body.error, 'not_configured');
    assertEquals(body.missing, ['PABBLY_AUTH_EMAIL_SHARED_SECRET', 'AUTH_EMAIL_FROM_ADDRESS']);
    // Without this header the page sees an opaque CORS failure instead of the
    // list of names, and a missing secret gets mistaken for a network problem.
    assertEquals(response.headers.get('Access-Control-Allow-Origin'), APP_URL);
  } finally {
    if (saved === undefined) Deno.env.delete('PUBLIC_APP_URL'); else Deno.env.set('PUBLIC_APP_URL', saved);
  }
});

Deno.test('an untrustworthy action link is never emailed', async () => {
  const { sent, deliver } = recordingDeliver();
  const response = await run(postRequest({ email: 'ada@example.com' }), resendEndpoint(flowDeps({
    deliver,
    accountState: () => Promise.resolve('confirmed'),
    affiliateEmailNeedsVerification: () => Promise.resolve(true),
    generateMagicLink: () => Promise.resolve({
      status: 'ok', link: { actionLink: 'https://evil.example/auth/v1/verify?token=x', email: 'ada@example.com', displayName: '' },
    }),
  })));
  assertEquals(response.status, 503);
  assertEquals(sent.length, 0);
});

Deno.test('an unlisted origin gets no CORS grant but is still answered', async () => {
  const response = await run(postRequest(validSignupBody, { origin: 'https://evil.example' }), signupEndpoint(flowDeps()));
  assertEquals(response.headers.get('Access-Control-Allow-Origin'), null);
  assertEquals(response.status, 200);
  assertNotEquals((await bodyOf(response)).status, undefined);
});
