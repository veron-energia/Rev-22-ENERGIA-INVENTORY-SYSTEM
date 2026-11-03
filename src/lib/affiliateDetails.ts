import { supabase } from './supabase';

// 491 (3 Nov 2026): an affiliate's own change of name, phone or email, and
// staff's decision on one that waits for them. Every step goes through the
// Edge Function affiliate-details; the portal reads affiliate_portal_details.

export type DetailsRoute = 'free' | 'code' | 'staff' | 'verify_first' | 'closed';

export interface DetailsRequest {
  id: string; route: 'free' | 'code' | 'staff';
  status: 'awaiting_code' | 'pending_staff' | 'applying' | 'applied' | 'rejected' | 'cancelled' | 'expired' | 'failed';
  new_first_name: string | null; new_last_name: string | null; new_phone: string | null; new_email: string | null;
  code_for: 'current' | 'new' | null; code_to: string | null; code_expires_at: string | null;
  created_at: string; decided_at: string | null; decision_note: string | null; applied_at: string | null;
}

/** affiliate_portal_details()'s answer. */
export interface PortalDetails {
  route: DetailsRoute; verified: boolean;
  first_name: string | null; last_name: string | null; phone: string | null; email: string | null; login_email: string | null;
  request: DetailsRequest | null;
}

export interface DetailsChanges { first_name?: string; last_name?: string; phone?: string; email?: string }

/** What a step came to: the next step, or why not (a code and a message). */
export interface DetailsStep {
  ok: boolean;
  next?: 'code' | 'pending_staff';
  status?: 'applied' | 'cancelled' | 'rejected';
  purpose?: 'current' | 'new';
  code_to?: string;
  request_id?: string;
  error?: string;
  field?: string;
  message?: string;
}

const MESSAGES: Record<string, string> = {
  verify_first: 'Please verify your email first, then you can change your details.',
  not_allowed: 'Your details cannot be changed here. Please ask Energia staff.',
  open_request: 'You already have a change in progress. Finish or cancel it first.',
  too_many_requests: 'You have made several changes today. Please try again tomorrow.',
  no_change: 'Nothing has changed.',
  name_required: 'Please enter your first and last name.',
  name_too_long: 'A name can be at most 50 characters.',
  name_characters: 'A name can have letters, spaces, hyphens, apostrophes, full stops, "/" and "@" only.',
  phone_invalid: 'Please enter a valid phone number, with its country code.',
  phone_in_use: 'This phone number belongs to another Energia customer. Please ask Energia staff for help.',
  email_invalid: 'Please enter a valid email address.',
  email_in_use: 'This email is already used by another Energia account. Please ask Energia staff for help.',
  wrong_code: 'That code is not right.',
  expired: 'That code has expired. Please start again.',
  too_many_tries: 'Too many wrong codes. Please start again.',
  wait: 'Please wait a minute before asking for another code.',
  too_many_sends: 'No more codes can be sent for this change. Please start again later.',
  no_request: 'This change is no longer open. Please start again.',
  not_sent: 'Energia could not send the code just now. Please try again.',
  email_not_changed: 'Your email could not be changed. Nothing was changed.',
  not_saved: 'Your change could not be saved. Nothing was changed. Please try again.',
  note_required: 'Please give a reason for rejecting it.',
  unauthorized: 'Your session has ended. Please sign in again.',
  unavailable: 'That could not be done just now. Please try again shortly.',
};

export function detailsMessage(error: string | undefined, extra: { tries_left?: number; seconds?: number } = {}): string {
  if (error === 'wrong_code' && typeof extra.tries_left === 'number') {
    return `That code is not right. ${extra.tries_left} ${extra.tries_left === 1 ? 'try' : 'tries'} left.`;
  }
  if (error === 'wait' && typeof extra.seconds === 'number') return `Please wait ${extra.seconds} seconds before asking for another code.`;
  return MESSAGES[error ?? ''] ?? MESSAGES.unavailable;
}

/** One step through affiliate-details, its refusal read from the answer's body. */
export async function detailsStep(body: Record<string, unknown>): Promise<DetailsStep> {
  const { data, error } = await supabase.functions.invoke('affiliate-details', { body });
  let payload: Record<string, unknown> = (data as Record<string, unknown>) ?? {};
  if (error) {
    const response = (error as { context?: unknown }).context;
    payload = response instanceof Response ? await response.json().catch(() => ({})) : { error: 'unavailable' };
  }
  if (error || payload.error) {
    const code = typeof payload.error === 'string' ? payload.error : 'unavailable';
    return { ok: false, error: code, field: payload.field as string | undefined,
      message: detailsMessage(code, { tries_left: payload.tries_left as number | undefined, seconds: payload.seconds as number | undefined }) };
  }
  return { ok: true, next: payload.next as DetailsStep['next'], status: payload.status as DetailsStep['status'],
    purpose: payload.purpose as DetailsStep['purpose'], code_to: payload.code_to as string | undefined,
    request_id: payload.request_id as string | undefined };
}
