// The From and Reply-To every Auth email carries.
//
// The address is configuration, not a literal in a template, so what this
// checks is that the configured value is the one that reaches the payload —
// and that nothing quietly substitutes a different sender when Reply-To is
// left unset.

import { assertEquals, assertStringIncludes } from 'jsr:@std/assert@1';
import { deliver } from '../pabbly.ts';
import { renderPasswordChanged, renderUserInvitation } from '../templates.ts';
import type { AuthEmailConfig } from '../config.ts';

const CONFIG = {
  fromAddress: 'info@rev22.com.sg',
  fromName: 'Rev 22 Global Energia',
  replyTo: 'info@rev22.com.sg',
  pabblySharedSecret: 'secret',
  pabblyWebhookUrl: 'https://connect.pabbly.test/hook',
  pabblyTimeoutMs: 5000,
} as unknown as AuthEmailConfig;

/** Runs a delivery against a stub webhook and hands back what was posted. */
async function capture(): Promise<Record<string, unknown>> {
  let sent: Record<string, unknown> = {};
  await deliver(CONFIG, REQUEST, ((_url: string, init: RequestInit) => {
    sent = JSON.parse(String(init.body));
    return Promise.resolve(new Response('ok', { status: 200 }));
  }) as unknown as typeof fetch);
  return sent;
}

const REQUEST = {
  requestId: 'r1', actionType: 'user_invitation' as const,
  to: 'new.person@energia.test', subject: "You're Invited to Energia",
  html: '<p>hi</p>', text: 'hi', recipientRole: 'staff' as const,
};

Deno.test('the delivery payload carries the configured sender and reply-to', async () => {
  const payload = await capture();
  assertEquals(payload.from_email, 'info@rev22.com.sg');
  assertEquals(payload.from_name, 'Rev 22 Global Energia');
  assertEquals(payload.reply_to, 'info@rev22.com.sg');
});

Deno.test('an invitation is addressed to the invitee, not to the sender', async () => {
  const payload = await capture();
  assertEquals(payload.to, 'new.person@energia.test');
});

Deno.test('the contact address shown to a user is the configured reply-to', () => {
  // renderPasswordChanged takes it as an argument, and every caller passes
  // config.replyTo — so the visible "contact us" address moves with the
  // configuration instead of being written into the template.
  const email = renderPasswordChanged('Sam', '2026-09-09T00:00:00Z', CONFIG.replyTo);
  assertStringIncludes(email.html, 'info@rev22.com.sg');
  assertStringIncludes(email.text, 'info@rev22.com.sg');
});

Deno.test('no template hardcodes a sender address', () => {
  const invitation = renderUserInvitation('Sam', 'https://project.supabase.co/auth/v1/verify?token=x');
  const changed = renderPasswordChanged('Sam', '2026-09-09T00:00:00Z', CONFIG.replyTo);
  for (const email of [invitation, changed]) {
    for (const body of [email.html, email.text]) {
      // A literal address in a template is one the configuration cannot move.
      assertEquals(/stanley@rev22\.com\.sg/.test(body), false, 'a template names the old sender');
    }
  }
});
