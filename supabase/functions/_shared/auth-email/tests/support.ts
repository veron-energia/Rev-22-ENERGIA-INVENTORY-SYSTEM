// Shared fixtures for the Auth-email tests.
//
// Nothing in here touches a network, a Supabase project or a real webhook, so
// the whole suite runs offline and the awkward cases — already-verified
// accounts, unknown addresses, a provider that times out — are as easy to test
// as the happy path.

import type { AuthEmailConfig } from '../config.ts';
import type { DeliveryRequest, DeliveryResult } from '../pabbly.ts';
import type { FlowDeps } from '../flows.ts';
import type { AccountState, GenerateOutcome } from '../admin.ts';

export const SUPABASE_URL = 'https://project.supabase.co';
export const APP_URL = 'https://rev-22-energia-inventory-system.vercel.app';

export function testConfig(overrides: Partial<AuthEmailConfig> = {}): AuthEmailConfig {
  return {
    supabaseUrl: SUPABASE_URL,
    serviceRoleKey: 'service-role-key',
    publicApiKey: 'sb_publishable_test',
    publicAppUrl: APP_URL,
    callbackBaseUrls: [APP_URL],
    allowedOrigins: [APP_URL],
    pabblyWebhookUrl: 'https://connect.pabbly.test/workflow/sendwebhookdata/TEST',
    pabblySharedSecret: 'shared-secret-value',
    fromAddress: 'stanley@rev22.com.sg',
    fromName: 'Rev 22 Global Energia',
    replyTo: 'stanley@rev22.com.sg',
    hashSecret: 'hash-secret-value',
    trustedProxyHops: 1,
    pabblyTimeoutMs: 10_000,
    ...overrides,
  };
}

export const ACTION_LINK = `${SUPABASE_URL}/auth/v1/verify?token=abc123&type=signup&redirect_to=${encodeURIComponent(APP_URL + '/affiliate/verify')}`;

export function okLink(email = 'someone@example.com', displayName = 'Ada Lovelace'): GenerateOutcome {
  return { status: 'ok', link: { actionLink: ACTION_LINK, email, displayName } };
}

export const acceptedDelivery: DeliveryResult = { outcome: 'accepted', httpStatus: 200, detail: '' };

/** A stand-in Supabase client that records the RPCs it was asked to run. */
export function fakeAdmin(handlers: Record<string, (args: Record<string, unknown>) => unknown> = {}) {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  return {
    calls,
    rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      const handler = handlers[fn];
      const data = handler ? handler(args) : null;
      if (data instanceof Error) return Promise.resolve({ data: null, error: { message: data.message } });
      return Promise.resolve({ data, error: null });
    },
  };
}

/** Always admits, so a test can get past the limiter to the thing it cares about. */
export const allowAll = {
  auth_email_reserve: () => ({ allowed: true, retry_after_seconds: 0 }),
  auth_email_record_outcome: () => null,
};

export interface Recorded { config: AuthEmailConfig; request: DeliveryRequest; }

export function recordingDeliver(result: DeliveryResult = acceptedDelivery) {
  const sent: Recorded[] = [];
  const deliver = (config: AuthEmailConfig, request: DeliveryRequest) => {
    sent.push({ config, request });
    return Promise.resolve(result);
  };
  return { sent, deliver };
}

export function flowDeps(overrides: Partial<FlowDeps> = {}): FlowDeps {
  return {
    accountState: () => Promise.resolve('none' as AccountState),
    generateSignupLink: () => Promise.resolve(okLink()),
    regenerateSignupLink: () => Promise.resolve(okLink()),
    generateRecoveryLink: () => Promise.resolve(okLink()),
    deliver: () => Promise.resolve(acceptedDelivery),
    normalizePhone: (raw) => (/^\+65[3689]\d{7}$/.test(raw) ? raw : null),
    ...overrides,
  };
}

export function postRequest(body: unknown, init: { origin?: string | null; headers?: Record<string, string> } = {}): Request {
  const headers: Record<string, string> = { 'Content-Type': 'application/json', ...(init.headers ?? {}) };
  if (init.origin !== null) headers.Origin = init.origin ?? APP_URL;
  return new Request('https://project.functions.supabase.co/auth-signup-request', {
    method: 'POST',
    headers,
    body: typeof body === 'string' ? body : JSON.stringify(body),
  });
}

export const validSignupBody = {
  first_name: 'Ada',
  last_name: 'Lovelace',
  phone: '+6591234567',
  email: 'Ada@Example.com',
  password: 'correct-horse-battery',
  terms_accepted: true,
};
