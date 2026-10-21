// End-to-end through the pipeline with every collaborator faked: the states that
// are hard to reproduce against a live project are the ones worth pinning down.

import { assert, assertEquals, assertFalse, assertNotEquals } from 'jsr:@std/assert@1';
import { EMAIL_IN_USE_MESSAGE, handlePublicRequest } from '../pipeline.ts';
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
  assertEquals(calls, ['state', 'create']);
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
    accountState: () => { order.push('state'); return Promise.resolve('none'); },
    createConfirmedSignup: () => { order.push('create'); return Promise.resolve({ status: 'error', message: 'down' }); },
  });

  await run(postRequest(validSignupBody), signupEndpoint(deps), admin);
  assertEquals(order, ['reserve', 'state', 'create']);
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
