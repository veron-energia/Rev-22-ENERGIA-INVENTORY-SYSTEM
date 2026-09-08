// Delivery: the payload Pabbly receives, and telling apart "accepted",
// "rejected" and "we have no idea".

import { assert, assertEquals, assertFalse } from 'jsr:@std/assert@1';
import { deliver, definitelyNotSent, type DeliveryRequest } from '../pabbly.ts';
import { testConfig } from './support.ts';

const request: DeliveryRequest = {
  requestId: '11111111-2222-3333-4444-555555555555',
  actionType: 'verify_signup',
  to: 'ada@example.com',
  subject: 'Verify Your Energia Affiliate Account',
  html: '<p>hi</p>',
  text: 'hi',
  recipientRole: 'affiliate',
};

Deno.test('the payload carries the secret, the sender and the finished message', async () => {
  type Seen = { url: string; init: RequestInit };
  const captured: Seen[] = [];
  const fake: typeof fetch = (url, init) => {
    captured.push({ url: String(url), init: init as RequestInit });
    return Promise.resolve(new Response('{"status":"success"}', { status: 200 }));
  };

  const config = testConfig();
  const result = await deliver(config, request, fake);
  assertEquals(result.outcome, 'accepted');
  assertEquals(result.httpStatus, 200);

  assertEquals(captured.length, 1);
  const sent = captured[0];
  assertEquals(sent.url, config.pabblyWebhookUrl);
  assertEquals(sent.init.method, 'POST');
  // A request id Pabbly can deduplicate on, without anyone claiming exactly-once.
  assertEquals((sent.init.headers as Record<string, string>)['Idempotency-Key'], request.requestId);

  const body = JSON.parse(String(sent.init.body));
  assertEquals(Object.keys(body).sort(), [
    'action_type', 'delivery_secret', 'from_email', 'from_name', 'html',
    'reply_to', 'request_id', 'subject', 'text', 'to', 'recipient_role',
  ].sort());
  assertEquals(body.delivery_secret, config.pabblySharedSecret);
  assertEquals(body.from_email, 'stanley@rev22.com.sg');
  assertEquals(body.from_name, 'Rev 22 Global Energia');
  assertEquals(body.reply_to, 'stanley@rev22.com.sg');
  assertEquals(body.to, 'ada@example.com');
  // No separate token or link field: the link is already in the message body.
  assertFalse('token' in body);
  assertFalse('action_link' in body);
});

Deno.test('a non-2xx is a rejection, and nothing was sent', async () => {
  const fake: typeof fetch = () => Promise.resolve(new Response('workflow disabled', { status: 400 }));
  const result = await deliver(testConfig(), request, fake);
  assertEquals(result.outcome, 'provider_rejected');
  assertEquals(result.httpStatus, 400);
  assert(definitelyNotSent(result.outcome));
});

Deno.test('an unreachable webhook is a failure, and nothing was sent', async () => {
  const fake: typeof fetch = () => Promise.reject(new TypeError('dns failure'));
  const result = await deliver(testConfig(), request, fake);
  assertEquals(result.outcome, 'failed');
  assert(definitelyNotSent(result.outcome));
});

Deno.test('a timeout is its own outcome, and is not treated as "not sent"', async () => {
  const config = testConfig({ pabblyTimeoutMs: 30 });
  const fake: typeof fetch = (_url, init) => new Promise((_resolve, reject) => {
    (init as RequestInit).signal?.addEventListener('abort', () => reject(new DOMException('aborted', 'AbortError')));
  });

  const started = Date.now();
  const result = await deliver(config, request, fake);
  assert(Date.now() - started < 2000, 'the wait must be bounded');

  assertEquals(result.outcome, 'timeout');
  // The crucial bit: Pabbly may already have accepted and sent it, so this is
  // not something to retry automatically and not something to report as failed.
  assertFalse(definitelyNotSent(result.outcome));
});

Deno.test('deliver sends exactly once — no built-in retry', async () => {
  let calls = 0;
  const fake: typeof fetch = () => { calls += 1; return Promise.resolve(new Response('', { status: 500 })); };
  await deliver(testConfig(), request, fake);
  assertEquals(calls, 1);
});

Deno.test('a chatty provider response is truncated before it is recorded', async () => {
  const fake: typeof fetch = () => Promise.resolve(new Response('x'.repeat(5000), { status: 500 }));
  const result = await deliver(testConfig(), request, fake);
  assert(result.detail.length <= 300);
});
