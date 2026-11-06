// An affiliate's own change of name, phone or email (affiliate-details, 491),
// without a Supabase project: the database answers and the senders are fakes.
//
//   D1 No token, a bad token, a bad action or request id: refused, nothing called.
//   D2 start, free: the change is applied at once; no code; the old address is told.
//   D3 start, code: a code goes to the current address, never into the answer.
//   D4 verify: the next code (a new email), the wait for staff, or the change.
//   D5 A new login email: Supabase Auth's admin API first, then the record; if the
//      admin API refuses, the request fails and the record is untouched; if the
//      record cannot be saved, the login's email is put back first.
//   D6 Refusals keep their meaning (409 phone_in_use, 403 verify_first, 400
//      wrong_code with tries left, 429 wait); a code the delivery service did
//      not take says not_sent.
//   D7 decide: approve applies, reject only records.
//   D8 (493) start with lost_inbox: the new database function, and the code goes
//      where it says (the new address); anything but true is the usual start.
//   D9 (493) a staff decision that changes the login's email tells the old and the
//      new address; one made with codes, or changing no email, tells the old alone.
// Every name and address is made up.

import { assert, assertEquals } from 'jsr:@std/assert@1';
import { handleDetailsRequest, type DetailsDeps, type RpcAnswer } from '../details.ts';
import { renderDetailsChanged, renderDetailsCode, SUBJECTS } from '../templates.ts';

const UID = '00000000-0000-4000-8000-000000000491';
const RID = '00000000-0000-4000-8000-0000000004a1';
const OLD = 'ada.old@example.com';
const NEW = 'ada.new@example.com';

interface World {
  answers?: Record<string, unknown | ((args: Record<string, unknown>) => unknown)>;
  user?: { id: string } | null;
  loginOk?: boolean | ((email: string) => boolean);
  sendOk?: boolean;
}

function world(w: World = {}) {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const emails: { kind: string; to: string; body: string }[] = [];
  const logins: string[] = [];
  const logs: string[] = [];
  const deps: DetailsDeps = {
    readUser: async (token) => (token === 'good' ? (w.user === undefined ? { id: UID } : w.user) : null),
    rpc: async (fn, args): Promise<RpcAnswer> => {
      calls.push({ fn, args });
      const a = w.answers?.[fn];
      const data = typeof a === 'function' ? (a as (x: Record<string, unknown>) => unknown)(args) : a;
      return data === undefined ? { data: null, error: { message: `no fake for ${fn}` } } : { data, error: null };
    },
    setLoginEmail: async (_id, email) => {
      logins.push(email);
      const ok = typeof w.loginOk === 'function' ? w.loginOk(email) : (w.loginOk ?? true);
      return ok ? { ok: true } : { ok: false, error: 'Email address already registered' };
    },
    sendCode: async (to, code, purpose) => { emails.push({ kind: `code:${purpose}`, to, body: code }); return w.sendOk ?? true; },
    sendChanged: async (to, changes) => { emails.push({ kind: 'changed', to, body: JSON.stringify(changes) }); return true; },
    log: (event, fields) => logs.push(`${event} ${JSON.stringify(fields)}`),
  };
  return { deps, calls, emails, logins, logs };
}

const applied = (changes: Record<string, string>, notifyTo = OLD) =>
  ({ request_id: RID, status: 'applied', changes, notify: { to: notifyTo, login_email_changed: !!changes.email } });
const plan = (login: string | null = null) => ({ request_id: RID, auth_user_id: UID, login_email: login, old_login_email: OLD });

Deno.test('D1: no token, a bad token, a bad action or request id are refused, and nothing is called', async () => {
  for (const [token, body, status] of [
    [null, { action: 'start' }, 401], ['bad', { action: 'start' }, 401], ['good', { action: 'delete' }, 400],
    ['good', { action: 'verify', request_id: 'nope', code: '123456' }, 400],
  ] as [string | null, Record<string, unknown>, number][]) {
    const t = world();
    const a = await handleDetailsRequest(token, body, t.deps);
    assertEquals(a.status, status, JSON.stringify(body));
    assertEquals(t.calls.length, 0);
    assertEquals(t.emails.length, 0);
  }
});

Deno.test('D2: a free change is applied at once, with no code, and the old address is told', async () => {
  const t = world({ answers: {
    affiliate_detail_change_start: { request_id: RID, route: 'free', next: 'apply', apply: plan() },
    affiliate_detail_change_finish: applied({ phone: '+61255500101' }),
  } });
  const a = await handleDetailsRequest('good', { action: 'start', changes: { phone: '+61 2 5550 0101', extra: 'x' } }, t.deps);
  assertEquals(a.status, 200);
  assertEquals(a.body.status, 'applied');
  assertEquals(t.calls[0].args, { p_uid: UID, p_new: { phone: '+61 2 5550 0101' } }, 'only the known keys, for the signed-in user');
  assertEquals(t.logins, [], 'the login email does not change');
  assertEquals(t.emails.map(e => `${e.kind} ${e.to}`), [`changed ${OLD}`]);
});

Deno.test('D3: a code goes to the current address and never into the answer or the logs', async () => {
  const t = world({ answers: {
    affiliate_detail_change_start: { request_id: RID, route: 'code', next: 'code', send: { to: OLD, code: '482913', purpose: 'current' } },
  } });
  const a = await handleDetailsRequest('good', { action: 'start', changes: { first_name: 'Ada' } }, t.deps);
  assertEquals(a.status, 200);
  assertEquals(a.body, { request_id: RID, next: 'code', purpose: 'current', code_to: OLD });
  assertEquals(t.emails, [{ kind: 'code:current', to: OLD, body: '482913' }]);
  assert(!JSON.stringify(a.body).includes('482913') && !t.logs.join('\n').includes('482913'));
});

Deno.test('D4: verify leads to the next code, the wait for staff, or the change', async () => {
  let t = world({ answers: { affiliate_detail_change_verify: { request_id: RID, next: 'code', send: { to: NEW, code: '120034', purpose: 'new' } } } });
  let a = await handleDetailsRequest('good', { action: 'verify', request_id: RID, code: '482913' }, t.deps);
  assertEquals(a.body, { request_id: RID, next: 'code', purpose: 'new', code_to: NEW });
  assertEquals(t.calls[0].args, { p_uid: UID, p_id: RID, p_code: '482913' });

  t = world({ answers: { affiliate_detail_change_verify: { request_id: RID, next: 'pending_staff' } } });
  a = await handleDetailsRequest('good', { action: 'verify', request_id: RID, code: '120034' }, t.deps);
  assertEquals(a.body, { request_id: RID, next: 'pending_staff' });
  assertEquals(t.emails.length, 0);

  t = world({ answers: {
    affiliate_detail_change_verify: { request_id: RID, next: 'apply', apply: plan() },
    affiliate_detail_change_finish: applied({ first_name: 'Ada' }),
  } });
  a = await handleDetailsRequest('good', { action: 'verify', request_id: RID, code: '120034' }, t.deps);
  assertEquals(a.body.status, 'applied');
});

Deno.test('D5: a new login email changes through the admin API first; a refusal or a failed save leaves nothing half done', async () => {
  // all well
  let t = world({ answers: {
    affiliate_detail_change_verify: { request_id: RID, next: 'apply', apply: plan(NEW) },
    affiliate_detail_change_finish: applied({ email: NEW }),
  } });
  let a = await handleDetailsRequest('good', { action: 'verify', request_id: RID, code: '120034' }, t.deps);
  assertEquals(a.body.status, 'applied');
  assertEquals(t.logins, [NEW]);
  assertEquals(t.calls.map(c => c.fn), ['affiliate_detail_change_verify', 'affiliate_detail_change_finish']);
  assertEquals(t.emails.map(e => e.to), [OLD], 'the OLD address is told');

  // the admin API refuses: the request fails, the record is untouched
  t = world({ loginOk: false, answers: {
    affiliate_detail_change_verify: { request_id: RID, next: 'apply', apply: plan(NEW) },
    affiliate_detail_change_finish: (args: Record<string, unknown>) => ({ request_id: RID, status: args.p_login_ok ? 'applied' : 'failed' }),
  } });
  a = await handleDetailsRequest('good', { action: 'verify', request_id: RID, code: '120034' }, t.deps);
  assertEquals(a.status, 409);
  assertEquals(a.body.error, 'email_not_changed');
  assertEquals(t.calls.filter(c => c.fn === 'affiliate_detail_change_finish').map(c => c.args.p_login_ok), [false]);

  // the record cannot be saved: the login's email is put back, then the request fails
  t = world({ answers: {
    affiliate_detail_change_verify: { request_id: RID, next: 'apply', apply: plan(NEW) },
    affiliate_detail_change_finish: (args: Record<string, unknown>) => (args.p_login_ok ? { error: 'not_applying' } : { request_id: RID, status: 'failed' }),
  } });
  a = await handleDetailsRequest('good', { action: 'verify', request_id: RID, code: '120034' }, t.deps);
  assertEquals(a.status, 503);
  assertEquals(t.logins, [NEW, OLD], 'changed, then put back');
  assertEquals(t.calls.filter(c => c.fn === 'affiliate_detail_change_finish').map(c => c.args.p_login_ok), [true, false]);
  assertEquals(t.emails.length, 0, 'nobody is told of a change that did not happen');
});

Deno.test('D6: refusals keep their meaning; a code the delivery service did not take says not_sent', async () => {
  for (const [answer, status] of [
    [{ error: 'phone_in_use', field: 'phone' }, 409], [{ error: 'verify_first' }, 403],
    [{ error: 'wrong_code', tries_left: 3 }, 400], [{ error: 'wait', seconds: 42 }, 429], [{ error: 'too_many_tries' }, 429],
  ] as [Record<string, unknown>, number][]) {
    const t = world({ answers: { affiliate_detail_change_start: answer } });
    const a = await handleDetailsRequest('good', { action: 'start', changes: { phone: '+61 2 5550 0102' } }, t.deps);
    assertEquals(a.status, status, String(answer.error));
    assertEquals(a.body, answer);
  }
  const t = world({ sendOk: false, answers: { affiliate_detail_change_resend: { request_id: RID, next: 'code', send: { to: OLD, code: '555000', purpose: 'current' } } } });
  const a = await handleDetailsRequest('good', { action: 'resend', request_id: RID }, t.deps);
  assertEquals(a.status, 502);
  assertEquals(a.body.error, 'not_sent');
  assertEquals(a.body, { error: 'not_sent', request_id: RID, purpose: 'current', code_to: OLD }, 'where the code was for: the request stays open at that step');
  const down = world();
  assertEquals((await handleDetailsRequest('good', { action: 'cancel', request_id: RID }, down.deps)).status, 503, 'the database not answering');
});

Deno.test('D7: an Owner\'s approval applies the change; a rejection only records it', async () => {
  let t = world({ answers: {
    affiliate_detail_change_decide: { request_id: RID, next: 'apply', apply: plan() },
    affiliate_detail_change_finish: applied({ phone: '+61255500103' }),
  } });
  let a = await handleDetailsRequest('good', { action: 'decide', request_id: RID, approve: true, note: 'Checked at the counter' }, t.deps);
  assertEquals(a.body.status, 'applied');
  assertEquals(t.calls[0].args, { p_staff_uid: UID, p_id: RID, p_approve: true, p_note: 'Checked at the counter' });

  t = world({ answers: { affiliate_detail_change_decide: { request_id: RID, status: 'rejected' } } });
  a = await handleDetailsRequest('good', { action: 'decide', request_id: RID, approve: false, note: 'Not the same person' }, t.deps);
  assertEquals(a.body, { request_id: RID, status: 'rejected' });
  assertEquals(t.calls.map(c => c.fn), ['affiliate_detail_change_decide']);

  t = world({ answers: { affiliate_detail_change_decide: { error: 'not_allowed' } } });
  a = await handleDetailsRequest('good', { action: 'decide', request_id: RID, approve: true }, t.deps);
  assertEquals(a.status, 403);
});

Deno.test('D8: start with lost_inbox goes to its own function, and the code to the new address alone', async () => {
  let t = world({ answers: { affiliate_detail_change_start_lost_inbox: { request_id: RID, route: 'staff', next: 'code', send: { to: NEW, code: '112233', purpose: 'new' } } } });
  const a = await handleDetailsRequest('good', { action: 'start', lost_inbox: true, changes: { email: NEW, junk: 'x' } }, t.deps);
  assertEquals(a.status, 200);
  assertEquals(a.body, { request_id: RID, next: 'code', purpose: 'new', code_to: NEW });
  assertEquals(t.calls, [{ fn: 'affiliate_detail_change_start_lost_inbox', args: { p_uid: UID, p_new: { email: NEW } } }]);
  assertEquals(t.emails, [{ kind: 'code:new', to: NEW, body: '112233' }]);
  assert(!JSON.stringify(a.body).includes('112233'), 'never in the answer');

  for (const flag of [false, 'true', 1, null, undefined]) {
    t = world({ answers: { affiliate_detail_change_start: { request_id: RID, route: 'code', next: 'code', send: { to: OLD, code: '445566', purpose: 'current' } } } });
    await handleDetailsRequest('good', { action: 'start', lost_inbox: flag, changes: { email: NEW } }, t.deps);
    assertEquals(t.calls.map(c => c.fn), ['affiliate_detail_change_start'], String(flag));
  }

  t = world({ answers: { affiliate_detail_change_start_lost_inbox: { error: 'new_email_required', field: 'email' } } });
  const refused = await handleDetailsRequest('good', { action: 'start', lost_inbox: true, changes: { first_name: 'Ada' } }, t.deps);
  assertEquals(refused.status, 400);
  assertEquals(refused.body.error, 'new_email_required');
  assertEquals(t.emails, []);
});

Deno.test('D9: a staff decision that changes the login\'s email tells the old and the new address', async () => {
  let t = world({ answers: {
    affiliate_detail_change_decide: { request_id: RID, next: 'apply', apply: plan(NEW) },
    affiliate_detail_change_finish: applied({ email: NEW }),
  } });
  let a = await handleDetailsRequest('good', { action: 'decide', request_id: RID, approve: true }, t.deps);
  assertEquals(a.body.status, 'applied');
  assertEquals(t.logins, [NEW]);
  assertEquals(t.emails.map(e => [e.kind, e.to]), [['changed', OLD], ['changed', NEW]]);

  // A staff decision that changes no email: the old address alone.
  t = world({ answers: {
    affiliate_detail_change_decide: { request_id: RID, next: 'apply', apply: plan() },
    affiliate_detail_change_finish: applied({ phone: '+61255500103' }),
  } });
  await handleDetailsRequest('good', { action: 'decide', request_id: RID, approve: true }, t.deps);
  assertEquals(t.emails.map(e => [e.kind, e.to]), [['changed', OLD]]);

  // Made with codes: the affiliate is there; the old address alone.
  t = world({ answers: {
    affiliate_detail_change_verify: { request_id: RID, next: 'apply', apply: plan(NEW) },
    affiliate_detail_change_finish: applied({ email: NEW }),
  } });
  a = await handleDetailsRequest('good', { action: 'verify', request_id: RID, code: '123456' }, t.deps);
  assertEquals(a.body.status, 'applied');
  assertEquals(t.emails.map(e => [e.kind, e.to]), [['changed', OLD]]);

  // Refused by Supabase Auth: nobody is told anything changed.
  t = world({ loginOk: false, answers: {
    affiliate_detail_change_decide: { request_id: RID, next: 'apply', apply: plan(NEW) },
    affiliate_detail_change_finish: { request_id: RID, status: 'failed' },
  } });
  a = await handleDetailsRequest('good', { action: 'decide', request_id: RID, approve: true }, t.deps);
  assertEquals(a.status, 409);
  assertEquals(t.emails, []);
});

Deno.test('the two emails: the code shows only six digits; the notice lists what changed', () => {
  const code = renderDetailsCode('482913', 'new');
  assertEquals(code.subject, SUBJECTS.details_code);
  assert(code.html.includes('482913') && code.text.includes('Your code: 482913'));
  assert(code.text.includes('confirm this new email address'));
  assert(!renderDetailsCode('<b>1</b>', 'current').html.includes('<b>1</b>'), 'anything but six digits is dropped');
  const notice = renderDetailsChanged({ first_name: 'Ada', last_name: 'Test', phone: '+61255500101', email: NEW }, '2026-11-03T04:00:00Z', 'info@example.com');
  assertEquals(notice.subject, 'Your Energia Details Were Changed');
  for (const s of ['Name: Ada Test', 'Phone: +61255500101', `Email: ${NEW}`, '2026-11-03 04:00 UTC', 'info@example.com']) assert(notice.text.includes(s), s);
  assert(!renderDetailsChanged({ first_name: '<script>' }, '2026-11-03T04:00:00Z', 'info@example.com').html.includes('<script>'));
  // 493: a new email says which one to sign in with; no new email, no such line.
  assert(notice.text.includes('From now on, sign in with your new email.') && notice.html.includes('From now on, sign in with your new email.'));
  const noEmail = renderDetailsChanged({ phone: '+61255500101' }, '2026-11-03T04:00:00Z', 'info@example.com');
  assert(!noEmail.text.includes('sign in with') && !noEmail.html.includes('sign in with'));
});
