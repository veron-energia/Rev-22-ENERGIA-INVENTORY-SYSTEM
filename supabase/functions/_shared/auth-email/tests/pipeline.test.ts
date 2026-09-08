// End-to-end through the pipeline with every collaborator faked: the states that
// are hard to reproduce against a live project are the ones worth pinning down.

import { assert, assertEquals, assertFalse, assertNotEquals } from 'jsr:@std/assert@1';
import { handlePublicRequest } from '../pipeline.ts';
import { recoveryEndpoint, resendEndpoint, signupEndpoint } from '../flows.ts';
import { MissingConfigError } from '../config.ts';
import {
  APP_URL, ACTION_LINK, allowAll, fakeAdmin, flowDeps, okLink,
  postRequest, recordingDeliver, testConfig, validSignupBody,
} from './support.ts';

// deno-lint-ignore no-explicit-any
const run = (req: Request, endpoint: any, admin = fakeAdmin(allowAll), config = testConfig()) =>
  handlePublicRequest(req, endpoint, { loadConfig: () => config, makeAdmin: () => admin });

const bodyOf = async (response: Response) => await response.json();

// ---------------------------------------------------------------------------
// Signup
// ---------------------------------------------------------------------------

Deno.test('a new signup creates the account and sends one verification email', async () => {
  const { sent, deliver } = recordingDeliver();
  const calls: string[] = [];
  const deps = flowDeps({
    deliver,
    accountState: () => { calls.push('state'); return Promise.resolve('none'); },
    generateSignupLink: (_a, args) => {
      calls.push('create');
      assertEquals(args.email, 'ada@example.com');
      assertEquals(args.redirectTo, `${APP_URL}/affiliate/verify`);
      assertEquals(args.metadata.role_hint, 'affiliate');
      return Promise.resolve(okLink('ada@example.com'));
    },
  });

  const response = await run(postRequest(validSignupBody), signupEndpoint(deps));
  assertEquals(response.status, 200);
  assertEquals((await bodyOf(response)).status, 'submitted');
  assertEquals(calls, ['state', 'create']);
  assertEquals(sent.length, 1);
  assertEquals(sent[0].request.to, 'ada@example.com');
  assertEquals(sent[0].request.actionType, 'verify_signup');
});

Deno.test('signing up again while unverified re-sends and never rewrites the account', async () => {
  const { sent, deliver } = recordingDeliver();
  let created = 0;
  let regenerated = 0;
  const deps = flowDeps({
    deliver,
    accountState: () => Promise.resolve('unconfirmed'),
    generateSignupLink: () => { created += 1; return Promise.resolve(okLink()); },
    // Note the arguments this path is even capable of passing: an email and a
    // redirect. No password, no metadata — so a second submission cannot reset
    // the password or overwrite the details of a pending account.
    regenerateSignupLink: (_a, args) => {
      regenerated += 1;
      assertEquals(Object.keys(args).sort(), ['email', 'redirectTo']);
      return Promise.resolve(okLink());
    },
  });

  const response = await run(postRequest({ ...validSignupBody, password: 'a-completely-different-password' }), signupEndpoint(deps));
  assertEquals(response.status, 200);
  assertEquals(created, 0, 'must not create a second account');
  assertEquals(regenerated, 1);
  assertEquals(sent.length, 1);
});

Deno.test('an already-verified address is sent nothing, and the response does not say so', async () => {
  const { sent, deliver } = recordingDeliver();
  const deps = flowDeps({ deliver, accountState: () => Promise.resolve('confirmed') });

  const verified = await run(postRequest(validSignupBody), signupEndpoint(deps));
  assertEquals(sent.length, 0, 'a verified account must not be re-mailed');

  const fresh = await run(postRequest(validSignupBody), signupEndpoint(flowDeps({ deliver: recordingDeliver().deliver })));

  assertEquals(verified.status, fresh.status);
  const a = await bodyOf(verified);
  const b = await bodyOf(fresh);
  assertEquals(a.status, b.status);
  assertEquals(Object.keys(a).sort(), Object.keys(b).sort());
  assertNotEquals(a.request_id, b.request_id);   // the only difference
});

Deno.test('a signup whose email fails to send keeps the account and asks for a retry', async () => {
  const { sent, deliver } = recordingDeliver({ outcome: 'provider_rejected', httpStatus: 400, detail: 'workflow disabled' });
  const admin = fakeAdmin(allowAll);
  let created = 0;
  const deps = flowDeps({ deliver, generateSignupLink: () => { created += 1; return Promise.resolve(okLink()); } });

  const response = await run(postRequest(validSignupBody), signupEndpoint(deps), admin);
  const body = await bodyOf(response);

  assertEquals(response.status, 200);
  assertEquals(body.ok, true);
  // Reported honestly so the page can offer Resend rather than promise an email.
  assertEquals(body.status, 'not_sent');
  assertEquals(created, 1, 'the account is created once and left alone');
  assertEquals(sent.length, 1, 'and delivery is attempted once, never retried here');

  const outcomes = admin.calls.filter(c => c.fn === 'auth_email_record_outcome').map(c => c.args.p_outcome);
  assertEquals(outcomes, ['requested', 'provider_rejected']);
});

Deno.test('an ambiguous timeout is not retried and is not reported as a failure', async () => {
  const { sent, deliver } = recordingDeliver({ outcome: 'timeout', httpStatus: null, detail: 'no response' });
  const admin = fakeAdmin(allowAll);
  const response = await run(postRequest(validSignupBody), signupEndpoint(flowDeps({ deliver })), admin);
  const body = await bodyOf(response);

  assertEquals(sent.length, 1, 'exactly one attempt: the message may already have gone');
  assertEquals(body.status, 'submitted', 'a timeout is not proof of failure');
  assertEquals(admin.calls.filter(c => c.fn === 'auth_email_record_outcome').at(-1)?.args.p_outcome, 'timeout');
});

// ---------------------------------------------------------------------------
// Resend
// ---------------------------------------------------------------------------

Deno.test('resend sends only for an account that exists and is unverified', async () => {
  for (const [state, expected] of [['none', 0], ['confirmed', 0], ['unconfirmed', 1]] as const) {
    const { sent, deliver } = recordingDeliver();
    let created = 0;
    const deps = flowDeps({
      deliver,
      accountState: () => Promise.resolve(state),
      generateSignupLink: () => { created += 1; return Promise.resolve(okLink()); },
    });
    const response = await run(postRequest({ email: 'ada@example.com' }), resendEndpoint(deps));
    assertEquals(response.status, 200, state);
    assertEquals(sent.length, expected, `state=${state}`);
    assertEquals(created, 0, 'resend must never create an account');
  }
});

Deno.test('resend answers identically for unknown, unverified and verified addresses', async () => {
  const bodies = [];
  for (const state of ['none', 'unconfirmed', 'confirmed'] as const) {
    const response = await run(postRequest({ email: 'ada@example.com' }), resendEndpoint(flowDeps({ accountState: () => Promise.resolve(state) })));
    assertEquals(response.status, 200);
    const body = await bodyOf(response);
    delete body.request_id;
    bodies.push(JSON.stringify(body));
  }
  assertEquals(new Set(bodies).size, 1, `bodies differed: ${bodies.join(' | ')}`);
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

Deno.test('no response ever carries the action link, a token or a secret', async () => {
  const config = testConfig();
  for (const [endpoint, body] of [
    [signupEndpoint(flowDeps()), validSignupBody],
    [resendEndpoint(flowDeps({ accountState: () => Promise.resolve('unconfirmed') })), { email: 'ada@example.com' }],
    [recoveryEndpoint(flowDeps()), { email: 'ada@example.com', flow: 'staff' }],
  ] as const) {
    const text = await (await run(postRequest(body), endpoint, fakeAdmin(allowAll), config)).text();
    for (const secret of [
      ACTION_LINK, 'abc123', '/auth/v1/verify', config.pabblySharedSecret,
      config.serviceRoleKey, config.hashSecret, config.pabblyWebhookUrl, validSignupBody.password,
    ]) {
      assertFalse(text.includes(secret), `response leaked: ${secret.slice(0, 40)}`);
    }
  }
});

Deno.test('a caller cannot choose the recipient, the content or the redirect', async () => {
  const { sent, deliver } = recordingDeliver();
  const attempt = {
    ...validSignupBody,
    to: 'victim@example.com',
    subject: 'Free money',
    html: '<p>spam</p>',
    redirect_to: 'https://evil.example/steal',
    role: 'service_role',
    from_email: 'spoof@rev22.com.sg',
  };
  const response = await run(postRequest(attempt), signupEndpoint(flowDeps({ deliver })));

  assertEquals(response.status, 400, 'an unknown field is refused, not ignored');
  assertEquals((await bodyOf(response)).error, 'invalid_request');
  assertEquals(sent.length, 0, 'nothing is sent while the shape is wrong');
});

Deno.test('even a valid request cannot influence sender, subject or recipient', async () => {
  const { sent, deliver } = recordingDeliver();
  const config = testConfig();
  await run(postRequest(validSignupBody), signupEndpoint(flowDeps({
    deliver,
    // Supabase reports the address it actually holds; that is what gets mailed.
    generateSignupLink: () => Promise.resolve(okLink('ada@example.com')),
  })), fakeAdmin(allowAll), config);

  assertEquals(sent[0].request.to, 'ada@example.com');
  assertEquals(sent[0].request.subject, 'Verify Your Energia Affiliate Account');
  assertEquals(sent[0].config.fromAddress, config.fromAddress);
  assertEquals(sent[0].config.fromName, config.fromName);
});

// ---------------------------------------------------------------------------
// Rate limiting and failure modes
// ---------------------------------------------------------------------------

Deno.test('a refused reservation stops before any link is generated or sent', async () => {
  const { sent, deliver } = recordingDeliver();
  let generated = 0;
  const admin = fakeAdmin({
    auth_email_reserve: () => ({ allowed: false, retry_after_seconds: 420, scope: 'email' }),
    auth_email_record_outcome: () => null,
  });
  const deps = flowDeps({ deliver, generateSignupLink: () => { generated += 1; return Promise.resolve(okLink()); } });

  const response = await run(postRequest(validSignupBody), signupEndpoint(deps), admin);
  const body = await bodyOf(response);

  assertEquals(response.status, 429);
  assertEquals(response.headers.get('Retry-After'), '420');
  assertEquals(body.error, 'rate_limited');
  assert(body.message.includes('7 minutes'), body.message);
  // Which bucket ran out is a fact about the account; it stays server-side.
  assertFalse(JSON.stringify(body).includes('email'));
  assertEquals(generated, 0);
  assertEquals(sent.length, 0);
});

Deno.test('the reservation is claimed before the link, and never handed back', async () => {
  const order: string[] = [];
  const admin = fakeAdmin({
    auth_email_reserve: () => { order.push('reserve'); return { allowed: true, retry_after_seconds: 0 }; },
    auth_email_record_outcome: () => null,
  });
  const deps = flowDeps({
    generateSignupLink: () => { order.push('generate'); return Promise.resolve(okLink()); },
    deliver: () => { order.push('deliver'); return Promise.resolve({ outcome: 'failed', httpStatus: null, detail: 'down' }); },
  });

  await run(postRequest(validSignupBody), signupEndpoint(deps), admin);
  assertEquals(order, ['reserve', 'generate', 'deliver']);
  // A failed send does not refund the slot: that is what caps retries.
  assertEquals(admin.calls.filter(c => c.fn === 'auth_email_reserve').length, 1);
});

Deno.test('a limiter that cannot answer fails closed', async () => {
  const { sent, deliver } = recordingDeliver();
  const admin = fakeAdmin({ auth_email_reserve: () => new Error('connection refused') });
  const response = await run(postRequest(validSignupBody), signupEndpoint(flowDeps({ deliver })), admin);

  assertEquals(response.status, 503);
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
  const response = await run(postRequest(validSignupBody), signupEndpoint(flowDeps({
    deliver,
    generateSignupLink: () => Promise.resolve({
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
});
