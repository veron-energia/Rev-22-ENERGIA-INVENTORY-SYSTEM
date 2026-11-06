// 491 (3 Nov 2026): an affiliate changes their own name, phone or email from
// the portal; an Owner or Manager decides the changes that wait for staff.
//
// The rules live in the database (affiliate_detail_change_* in
// supabase/491_affiliate_changes_own_details.sql, run here as the service
// role); this file only runs the steps in order:
//
//   start  -> free:  apply now
//          -> code:  email a code to the login's current address
//          -> (493, lost_inbox) email a code to the new address; staff decide
//   verify -> next code (a new email proves itself) | pending_staff | apply
//   resend -> another code for the same step
//   cancel
//   decide -> (staff) approve: apply | reject
//
// Apply: when the login's email changes, Supabase Auth's admin API changes it
// first (keeping auth.identities in step); then affiliate_detail_change_finish
// changes the record and the account. If finish fails, the login's email is
// put back first (while the request is still 'applying', so the trigger on
// auth.users knows it as the portal's own) and the request is marked failed.
// The old address is told what changed; after a staff decision the new one
// too (493): the affiliate is not there to see it, and signs in with it now.
//
// Codes come from the database once, go into the email and nowhere else: they
// are never in a response, a log line or an outcome row.

export type DetailsAction = 'start' | 'verify' | 'resend' | 'cancel' | 'decide';

export interface RpcAnswer { data: unknown; error: { message: string } | null }

export interface DetailsDeps {
  /** The signed-in user the token belongs to, or null. */
  readUser(token: string): Promise<{ id: string } | null>;
  /** A database function, as the service role. */
  rpc(fn: string, args: Record<string, unknown>): Promise<RpcAnswer>;
  /** Change a login's email (already proven, or the free route), confirmed. */
  setLoginEmail(userId: string, email: string): Promise<{ ok: boolean; error?: string }>;
  /** Email a code; true when the delivery service accepted it. */
  sendCode(to: string, code: string, purpose: 'current' | 'new'): Promise<boolean>;
  /** Tell an address what changed; best effort. */
  sendChanged(to: string, changes: Record<string, string>): Promise<boolean>;
  log(event: string, fields: Record<string, string | number | boolean | null>): void;
}

export interface DetailsAnswer { status: number; body: Record<string, unknown> }

const ACTIONS: readonly DetailsAction[] = ['start', 'verify', 'resend', 'cancel', 'decide'];
const CHANGE_KEYS = ['first_name', 'last_name', 'phone', 'email'] as const;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// The database's refusals, and the HTTP status each goes back with.
const STATUS_FOR: Record<string, number> = {
  invalid_request: 400, name_required: 400, name_too_long: 400, name_characters: 400, phone_invalid: 400,
  email_invalid: 400, new_email_required: 400, no_change: 400, wrong_code: 400, expired: 410, too_many_tries: 429, too_many_sends: 429,
  wait: 429, too_many_requests: 429, phone_in_use: 409, email_in_use: 409, open_request: 409, verify_first: 403,
  not_allowed: 403, no_request: 404, note_required: 400, not_applying: 409, unavailable: 503,
};

const refuse = (body: Record<string, unknown>): DetailsAnswer =>
  ({ status: STATUS_FOR[String(body.error)] ?? 400, body });

export async function handleDetailsRequest(token: string | null, body: Record<string, unknown>, deps: DetailsDeps): Promise<DetailsAnswer> {
  const action = body.action as DetailsAction;
  if (!ACTIONS.includes(action)) return { status: 400, body: { error: 'invalid_request' } };
  if (!token) return { status: 401, body: { error: 'unauthorized' } };
  const user = await deps.readUser(token);
  if (!user) return { status: 401, body: { error: 'unauthorized' } };

  const requestId = typeof body.request_id === 'string' && UUID.test(body.request_id) ? body.request_id : null;
  if (action !== 'start' && !requestId) return { status: 400, body: { error: 'invalid_request' } };

  if (action === 'start') {
    const raw = (body.changes && typeof body.changes === 'object') ? body.changes as Record<string, unknown> : {};
    const changes: Record<string, string> = {};
    for (const k of CHANGE_KEYS) if (typeof raw[k] === 'string') changes[k] = raw[k] as string;
    // 493: they cannot open their current email: the code goes to the new one, and staff decide.
    const fn = body.lost_inbox === true ? 'affiliate_detail_change_start_lost_inbox' : 'affiliate_detail_change_start';
    const answer = await call(deps, fn, { p_uid: user.id, p_new: changes });
    return next(deps, answer);
  }
  if (action === 'verify') {
    const code = typeof body.code === 'string' ? body.code : '';
    return next(deps, await call(deps, 'affiliate_detail_change_verify', { p_uid: user.id, p_id: requestId, p_code: code }));
  }
  if (action === 'resend') {
    return next(deps, await call(deps, 'affiliate_detail_change_resend', { p_uid: user.id, p_id: requestId }));
  }
  if (action === 'cancel') {
    const answer = await call(deps, 'affiliate_detail_change_cancel', { p_uid: user.id, p_id: requestId });
    return answer.error ? refuse(answer) : { status: 200, body: { request_id: requestId, status: 'cancelled' } };
  }
  // decide (staff): the database checks the login is an active Owner or Manager.
  const answer = await call(deps, 'affiliate_detail_change_decide', {
    p_staff_uid: user.id, p_id: requestId, p_approve: body.approve === true,
    p_note: typeof body.note === 'string' ? body.note : null,
  });
  if (answer.status === 'rejected') return { status: 200, body: { request_id: requestId, status: 'rejected' } };
  return next(deps, answer, true);
}

/** A database function's answer as an object; a failed call is 'unavailable'. */
async function call(deps: DetailsDeps, fn: string, args: Record<string, unknown>): Promise<Record<string, unknown>> {
  const { data, error } = await deps.rpc(fn, args);
  if (error || !data || typeof data !== 'object') {
    deps.log('affiliate_details.rpc_failed', { fn, detail: error ? String(error.message).slice(0, 200) : 'no answer' });
    return { error: 'unavailable' };
  }
  return data as Record<string, unknown>;
}

/** What follows an answer: a refusal, a code to email, a wait for staff, or the change itself. */
async function next(deps: DetailsDeps, answer: Record<string, unknown>, staffDecided = false): Promise<DetailsAnswer> {
  if (answer.error === 'unavailable') return { status: 503, body: { error: 'unavailable' } };
  if (answer.error) return refuse(answer);
  const requestId = answer.request_id;
  if (answer.next === 'code') {
    const send = answer.send as { to?: string; code?: string; purpose?: 'current' | 'new' } | undefined;
    if (!send?.to || !send.code || (send.purpose !== 'current' && send.purpose !== 'new')) return { status: 503, body: { error: 'unavailable' } };
    const sent = await deps.sendCode(send.to, send.code, send.purpose);
    deps.log('affiliate_details.code_sent', { purpose: send.purpose, accepted: sent });
    if (!sent) return { status: 502, body: { error: 'not_sent', request_id: requestId } };
    return { status: 200, body: { request_id: requestId, next: 'code', purpose: send.purpose, code_to: send.to } };
  }
  if (answer.next === 'pending_staff') return { status: 200, body: { request_id: requestId, next: 'pending_staff' } };
  if (answer.next === 'apply') return apply(deps, answer.apply as Record<string, unknown>, staffDecided);
  return { status: 503, body: { error: 'unavailable' } };
}

async function apply(deps: DetailsDeps, plan: Record<string, unknown> | undefined, staffDecided: boolean): Promise<DetailsAnswer> {
  const id = typeof plan?.request_id === 'string' ? plan.request_id : null;
  const userId = typeof plan?.auth_user_id === 'string' ? plan.auth_user_id : null;
  if (!id || !userId) return { status: 503, body: { error: 'unavailable' } };
  const newLogin = typeof plan?.login_email === 'string' ? plan.login_email : null;
  const oldLogin = typeof plan?.old_login_email === 'string' ? plan.old_login_email : null;

  if (newLogin) {
    const changed = await deps.setLoginEmail(userId, newLogin);
    if (!changed.ok) {
      deps.log('affiliate_details.login_email_not_changed', { detail: String(changed.error ?? '').slice(0, 200) });
      await deps.rpc('affiliate_detail_change_finish', { p_id: id, p_login_ok: false, p_failure: 'login email not changed' });
      return { status: 409, body: { error: 'email_not_changed', request_id: id } };
    }
  }
  const finished = await call(deps, 'affiliate_detail_change_finish', { p_id: id, p_login_ok: true, p_failure: null });
  if (finished.status !== 'applied') {
    // Put the login's email back while the request is still 'applying'.
    if (newLogin && oldLogin) {
      const back = await deps.setLoginEmail(userId, oldLogin);
      if (!back.ok) deps.log('affiliate_details.login_email_not_put_back', { request_id: id });
    }
    await deps.rpc('affiliate_detail_change_finish', { p_id: id, p_login_ok: false, p_failure: 'record not saved' });
    return { status: 503, body: { error: 'not_saved', request_id: id } };
  }
  const changes = (finished.changes ?? {}) as Record<string, string>;
  const notifyTo = (finished.notify as { to?: string } | undefined)?.to;
  if (notifyTo) {
    const told = await deps.sendChanged(notifyTo, changes);
    deps.log('affiliate_details.changed_notice', { accepted: told });
  }
  if (staffDecided && newLogin) {
    const told = await deps.sendChanged(newLogin, changes);
    deps.log('affiliate_details.changed_notice_new_email', { accepted: told });
  }
  return { status: 200, body: { request_id: id, status: 'applied', changes } };
}
