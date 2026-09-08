// The real collaborators for flows.ts. Isolated here so the flow logic stays
// importable — and testable — without the Supabase SDK or a network.

import { accountState, generateRecoveryLink, generateSignupLink, regenerateSignupLink } from './admin.ts';
import { deliver } from './pabbly.ts';
import { normalizePhone } from './phone.ts';
import type { FlowDeps } from './flows.ts';

export const liveDeps: FlowDeps = {
  accountState,
  generateSignupLink,
  regenerateSignupLink,
  generateRecoveryLink,
  deliver: (config, request) => deliver(config, request),
  normalizePhone,
};
