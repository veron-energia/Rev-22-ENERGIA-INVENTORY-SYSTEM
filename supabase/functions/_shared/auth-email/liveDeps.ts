// The real collaborators for flows.ts. Isolated here so the flow logic stays
// importable — and testable — without the Supabase SDK or a network.

import {
  accountState, affiliateEmailNeedsVerification, createConfirmedSignup, generateMagicLink,
  generateRecoveryLink, regenerateSignupLink,
} from './admin.ts';
import { deliver } from './pabbly.ts';
import { normalizePhone } from './phone.ts';
import type { FlowDeps } from './flows.ts';

export const liveDeps: FlowDeps = {
  accountState,
  createConfirmedSignup,
  regenerateSignupLink,
  generateMagicLink,
  affiliateEmailNeedsVerification,
  generateRecoveryLink,
  deliver: (config, request) => deliver(config, request),
  normalizePhone,
};
