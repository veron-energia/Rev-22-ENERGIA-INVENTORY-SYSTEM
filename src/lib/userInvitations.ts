import { supabase } from './supabase';

/**
 * Talking to the invitation endpoints.
 *
 * Everything that decides anything happens on the server. This file sends a
 * request and turns the answer into something the page can show; it never
 * decides who may invite whom, and it never receives an invitation link — the
 * server does not return one.
 */

export type InviteRole = 'owner' | 'admin' | 'manager' | 'inventory_manager' | 'staff';

export interface InviteFields {
  fullName: string;
  email: string;
  role: InviteRole;
  workPhone: string;
  personalPhone: string;
  personalEmail: string;
  storeIds: string[];
}

export type InviteOutcome =
  | { kind: 'invited'; invitationId: string; email: string; delivery: 'accepted_by_provider' | 'failed'; detail?: string }
  | { kind: 'field_error'; field: string; message: string }
  | { kind: 'forbidden'; message: string }
  | { kind: 'email_in_use'; message: string }
  | { kind: 'already_invited'; invitationId: string; message: string }
  | { kind: 'rate_limited'; message: string; retryAfterSeconds?: number }
  | { kind: 'failed'; message: string };

const UNREACHABLE =
  'We could not reach the server. Check your connection and try again — nothing was created.';

async function call(body: Record<string, unknown>): Promise<{ status: number; payload: Record<string, unknown> }> {
  const { data, error } = await supabase.functions.invoke('admin-invite-user', { body });
  if (!error) return { status: 200, payload: (data ?? {}) as Record<string, unknown> };

  const response = (error as { context?: unknown }).context;
  if (response instanceof Response) {
    const payload = await response.json().catch(() => ({}));
    return { status: response.status, payload: payload as Record<string, unknown> };
  }
  return { status: 0, payload: {} };
}

/** A request id that survives a retry, so a second click cannot create a second person. */
export const newRequestId = (): string =>
  (crypto.randomUUID?.() ?? `req-${Date.now()}-${Math.random().toString(36).slice(2)}`)
    .replace(/[^A-Za-z0-9_-]/g, '').slice(0, 64);

function interpret(status: number, payload: Record<string, unknown>): InviteOutcome {
  const message = typeof payload.message === 'string' ? payload.message : null;
  if (status === 200 && payload.ok) {
    return {
      kind: 'invited',
      invitationId: String(payload.invitation_id ?? ''),
      email: String(payload.email ?? ''),
      delivery: payload.delivery === 'accepted_by_provider' ? 'accepted_by_provider' : 'failed',
      detail: typeof payload.detail === 'string' ? payload.detail : undefined,
    };
  }
  if (status === 0) return { kind: 'failed', message: UNREACHABLE };
  if (payload.error === 'invalid_request') {
    return { kind: 'field_error', field: String(payload.field ?? 'email'), message: message ?? 'Check this field.' };
  }
  if (payload.error === 'forbidden') return { kind: 'forbidden', message: message ?? 'You are not permitted to do that.' };
  if (payload.error === 'email_in_use') return { kind: 'email_in_use', message: message ?? 'That address already has an account.' };
  if (payload.error === 'already_invited') {
    return { kind: 'already_invited', invitationId: String(payload.invitation_id ?? ''), message: message ?? 'Already invited.' };
  }
  if (payload.error === 'rate_limited') {
    return {
      kind: 'rate_limited', message: message ?? 'Please wait before trying again.',
      retryAfterSeconds: typeof payload.retry_after_seconds === 'number' ? payload.retry_after_seconds : undefined,
    };
  }
  if (payload.error === 'not_configured') {
    return { kind: 'failed', message: 'Invitation email is not configured on the server yet.' };
  }
  return { kind: 'failed', message: message ?? 'Something went wrong. Nothing was changed.' };
}

export async function inviteUser(fields: InviteFields, requestId: string): Promise<InviteOutcome> {
  const { status, payload } = await call({
    action: 'create',
    request_id: requestId,
    full_name: fields.fullName,
    email: fields.email,
    role: fields.role,
    work_phone: fields.workPhone,
    personal_phone: fields.personalPhone,
    personal_email: fields.personalEmail,
    store_ids: fields.storeIds,
  });
  return interpret(status, payload);
}

export async function resendInvitation(invitationId: string): Promise<InviteOutcome> {
  const { status, payload } = await call({ action: 'resend', invitation_id: invitationId });
  return interpret(status, payload);
}

export async function cancelInvitation(invitationId: string, reason: string):
  Promise<{ ok: true } | { ok: false; message: string }> {
  const { status, payload } = await call({ action: 'cancel', invitation_id: invitationId, reason });
  if (status === 200 && payload.ok) return { ok: true };
  if (status === 0) return { ok: false, message: UNREACHABLE };
  return { ok: false, message: typeof payload.message === 'string' ? payload.message : 'The invitation could not be cancelled.' };
}

/** Setting a password from an invitation link, and being activated on the strength of it. */
export type AcceptOutcome =
  | { kind: 'activated'; role?: string }
  | { kind: 'invalid_link'; message: string }
  | { kind: 'password_rejected'; message: string }
  | { kind: 'refused'; reason?: string; message: string }
  | { kind: 'failed'; message: string };

export async function acceptInvitation(password: string): Promise<AcceptOutcome> {
  const { data, error } = await supabase.functions.invoke('auth-accept-invitation', { body: { password } });
  if (!error) {
    const payload = (data ?? {}) as Record<string, unknown>;
    return { kind: 'activated', role: typeof payload.role === 'string' ? payload.role : undefined };
  }
  const response = (error as { context?: unknown }).context;
  if (!(response instanceof Response)) return { kind: 'failed', message: UNREACHABLE };

  const payload = (await response.json().catch(() => ({}))) as Record<string, unknown>;
  const message = typeof payload.message === 'string' ? payload.message : 'Something went wrong.';
  if (response.status === 401) return { kind: 'invalid_link', message };
  if (payload.error === 'password_rejected') return { kind: 'password_rejected', message };
  if (payload.error === 'not_activated') {
    return { kind: 'refused', reason: typeof payload.reason === 'string' ? payload.reason : undefined, message };
  }
  return { kind: 'failed', message };
}

/** Which roles this administrator may assign, answered by the database. */
export async function loadAssignableRoles(): Promise<InviteRole[]> {
  const { data, error } = await supabase.rpc('assignable_roles');
  if (error || !Array.isArray(data)) return [];
  return data as InviteRole[];
}

export async function loadAssignableStoreIds(): Promise<string[]> {
  const { data, error } = await supabase.rpc('assignable_store_ids');
  if (error || !Array.isArray(data)) return [];
  return data as string[];
}
