// An affiliate changes their own name, phone and email (491; the user, 3 Nov
// 2026): the Account page's Your details, the staff panel and the payout
// note, rendered for real against a fake backend.
//
//   Q1 Free (unverified, own record): edit, save, changed at once.
//   Q2 Code: a code to the current email, then one to a new email; the code
//      box is a one-time-code field; then changed.
//   Q3 A wrong code says how many tries are left; a new code waits a minute.
//   Q4 Staff: after the codes it waits for staff, can be cancelled; a
//      rejection shows staff's note.
//   Q5 Verify first, and closed: no way to edit, and why.
//   Q6 The staff panel: old -> asked for, the sign-up details; a rejection
//      needs a note; an approval is sent as decide.
//   Q7 The payout window's note when the affiliate changed their phone.
// Every name, phone and email is invented.
// Run: node --test scripts/affiliate-signup/tests/details-pages-491.test.mjs
import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import { setupDom, bundle, fakeSupabase, driver, tokenWith } from '../../ui/page-harness.mjs';

const dom = setupDom('https://energia.invalid/affiliate/account');
const mod = await bundle(`
  import React from 'react';
  export { default as AffiliateAccountPage } from './src/pages/AffiliateAccountPage';
  export { default as DetailChangeRequestsPanel } from './src/components/DetailChangeRequestsPanel';
  export { default as SelfPhoneChangeNote } from './src/components/commissions/SelfPhoneChangeNote';
  export { AffiliateProtected } from './src/components/RouteGuards';
  export { AuthProvider } from './src/context/AuthContext';
  export { MemoryRouter, Routes, Route } from 'react-router-dom';
  export { createRoot } from 'react-dom/client';
  export { act } from 'react';
  export { React };`);
const { React, AuthProvider, AffiliateProtected, MemoryRouter, Routes, Route } = mod;
const d = driver(mod, dom);
const h = React.createElement;
after(async () => { await d.unmount(); dom.window.close(); });

const UID = '00000000-0000-4000-8000-000000000491';
const RID = '00000000-0000-4000-8000-0000000004b1';
const LOGIN = 'ria-491@example.com';
const NEWMAIL = 'ria-new-491@example.com';

function details(over = {}) {
  return { route: 'code', verified: true, first_name: 'Ria', last_name: 'Test', phone: '+61255500111', email: LOGIN, login_email: LOGIN, request: null, ...over };
}

/** A signed-in affiliate; `steps` answers affiliate-details in turn. */
function backend({ portal = details(), steps = [] } = {}) {
  const session = { access_token: tokenWith({ sub: UID, role: 'authenticated', amr: [{ method: 'password', timestamp: Math.floor(Date.now() / 1000) - 60 }] }),
    user: { id: UID, email: LOGIN, user_metadata: {} } };
  const state = { portal };
  const client = fakeSupabase({
    auth: { session, getSession: async () => ({ data: { session } }), onAuthStateChange: () => ({ data: { subscription: { unsubscribe() {} } } }),
      signOut: async () => ({}), refreshSession: async () => ({ data: {} }) },
    tables: { profiles: [], affiliate_accounts: [{ id: 'acct-1', auth_user_id: UID, customer_id: 'cust-1', affiliate_id: 'aff-1', status: 'claimed',
      email_verified_at: portal.verified ? '2026-11-01T02:00:00Z' : null }] },
    rpc: {
      affiliate_portal_me: () => ({ customer_id: 'cust-1', name: 'Ria Test', email: LOGIN, referral_code: 'T491RIA', status: 'active', joined_at: '2026-10-01T02:00:00Z' }),
      affiliate_portal_details: () => state.portal,
    },
    invoke: {
      'affiliate-details': body => {
        const next = steps.shift();
        if (!next) return { data: { error: 'unavailable' }, error: null };
        const answer = typeof next === 'function' ? next(body, state) : next;
        if (answer.error && answer.status) return { data: null, error: { context: new Response(JSON.stringify(answer.body), { status: answer.status }) } };
        return { data: answer, error: null };
      },
    },
  });
  globalThis.__supabase = client;
  return { client, state };
}
const app = () => h(MemoryRouter, { initialEntries: ['/affiliate/account'] },
  h(AuthProvider, null, h(Routes, null, h(Route, { path: '/affiliate/account', element: h(AffiliateProtected, null, h(mod.AffiliateAccountPage)) }))));
const card = () => document.querySelector('[data-section="your-details"]');
const sent = client => client.calls.filter(c => c.fn === 'affiliate-details').map(c => c.body);
async function editTo(values) {
  await d.click(d.button('Change my details', card()));
  if (values.first) await d.setValue(document.getElementById('details-first'), values.first);
  if (values.email) await d.setValue(document.getElementById('details-email'), values.email);
  if (values.phone) await d.setValue(card().querySelector('input[type="tel"]'), values.phone);
}

test('Q1: free: edit, save, changed at once', async () => {
  const { client, state } = backend({ portal: details({ route: 'free', verified: false }), steps: [
    (body, s) => { s.portal = { ...s.portal, phone: '+61255500122' }; return { request_id: RID, status: 'applied', changes: { phone: '+61255500122' } }; },
  ] });
  await d.mount(app()); await d.tick(10);
  assert.equal(card().getAttribute('data-route'), 'free');
  assert.match(card().textContent, /Ria Test.*\+61255500111.*ria-491@example\.com/);
  await editTo({ phone: '+61 2 5550 0122' });
  await d.click(d.button('Save changes', card()));
  await d.tick(5);
  assert.equal(sent(client).length, 1);
  assert.equal(sent(client)[0].action, 'start');
  assert.ok(sent(client)[0].changes.phone, 'the phone is sent');
  assert.equal(Object.keys(sent(client)[0].changes).length, 1, 'only what changed');
  assert.match(card().textContent, /Your details were changed\./);
  assert.match(card().textContent, /\+61255500122/, 'read again after the change');
  assert.equal(state.portal.phone, '+61255500122');
});

test('Q2: code: the current email, then the new one, then changed', async () => {
  const { client } = backend({ steps: [
    { request_id: RID, next: 'code', purpose: 'current', code_to: LOGIN },
    { request_id: RID, next: 'code', purpose: 'new', code_to: NEWMAIL },
    (body, s) => { s.portal = { ...s.portal, email: NEWMAIL, login_email: NEWMAIL }; return { request_id: RID, status: 'applied', changes: { email: NEWMAIL } }; },
  ] });
  await d.mount(app()); await d.tick(10);
  await editTo({ email: NEWMAIL });
  assert.match(card().textContent, /Energia will email a code to ria-491@example\.com before changing anything, and one to your new email\./);
  await d.click(d.button('Save changes', card()));
  const box = document.getElementById('details-code');
  assert.ok(box, 'the code box');
  assert.equal(box.getAttribute('inputmode'), 'numeric');
  assert.equal(box.getAttribute('autocomplete'), 'one-time-code');
  assert.match(card().textContent, /Energia sent a 6-digit code to ria-491@example\.com\./);
  await d.setValue(box, '12a3456');
  assert.equal(box.value, '123456', 'digits only, six at most');
  await d.click(d.button('Confirm', card()));
  assert.match(card().textContent, /Now enter the 6-digit code Energia sent to your new email, ria-new-491@example\.com\./);
  await d.setValue(document.getElementById('details-code'), '654321');
  await d.click(d.button('Confirm', card()));
  await d.tick(5);
  assert.deepEqual(sent(client).map(b => b.action), ['start', 'verify', 'verify']);
  assert.deepEqual(sent(client).slice(1).map(b => [b.request_id, b.code]), [[RID, '123456'], [RID, '654321']]);
  assert.match(card().textContent, /Your details were changed\./);
  assert.match(card().textContent, /ria-new-491@example\.com/);
});

test('Q3: a wrong code says how many tries are left; a new code waits a minute', async () => {
  backend({ steps: [
    { request_id: RID, next: 'code', purpose: 'current', code_to: LOGIN },
    { error: 'wrong_code', status: 400, body: { error: 'wrong_code', tries_left: 3 } },
  ] });
  await d.mount(app()); await d.tick(10);
  await editTo({ first: 'Riana' });
  await d.click(d.button('Save changes', card()));
  await d.setValue(document.getElementById('details-code'), '111111');
  await d.click(d.button('Confirm', card()));
  assert.match(card().querySelector('[role="alert"]')?.textContent ?? '', /That code is not right\. 3 tries left\./);
  const resend = [...card().querySelectorAll('button')].find(b => b.textContent.startsWith('Send a new code'));
  assert.equal(resend.disabled, true);
  assert.match(resend.textContent, /Send a new code \(\d+s\)/);
});

test('Q4: staff: it waits after the codes, can be cancelled; a rejection shows the note', async () => {
  const { client } = backend({ portal: details({ route: 'staff' }), steps: [
    { request_id: RID, next: 'code', purpose: 'current', code_to: LOGIN },
    (body, s) => { s.portal = { ...s.portal, request: { id: RID, route: 'staff', status: 'pending_staff' } }; return { request_id: RID, next: 'pending_staff' }; },
    (body, s) => { s.portal = { ...s.portal, request: { id: RID, route: 'staff', status: 'cancelled' } }; return { request_id: RID, status: 'cancelled' }; },
  ] });
  await d.mount(app()); await d.tick(10);
  await editTo({ first: 'Riana' });
  assert.match(card().textContent, /Then Energia staff check the change before it is made\./);
  await d.click(d.button('Save changes', card()));
  await d.setValue(document.getElementById('details-code'), '222222');
  await d.click(d.button('Confirm', card()));
  await d.tick(5);
  assert.match(card().textContent, /Your change was sent to Energia staff, who will check it\./);
  assert.ok(card().querySelector('[data-state="waiting"]'));
  await d.click(d.button('Cancel the change', card()));
  await d.tick(5);
  assert.equal(sent(client).at(-1).action, 'cancel');
  assert.match(card().textContent, /The change was cancelled\./);

  backend({ portal: details({ route: 'staff', request: { id: RID, route: 'staff', status: 'rejected', decision_note: 'Please come to the counter with your NRIC' } }) });
  await d.mount(app()); await d.tick(10);
  assert.match(card().textContent, /Energia staff did not approve your last change: Please come to the counter with your NRIC/);
});

test('Q5: verify first, and closed: no way to edit, and why', async () => {
  backend({ portal: details({ route: 'verify_first', verified: false }) });
  await d.mount(app()); await d.tick(10);
  assert.equal(d.button('Change my details', card()), undefined);
  assert.match(card().textContent, /Please verify your email first/);
  backend({ portal: details({ route: 'closed' }) });
  await d.mount(app()); await d.tick(10);
  assert.equal(d.button('Change my details', card()), undefined);
  assert.match(card().textContent, /cannot be changed here/);
});

test('Q6: the staff panel: what changes, the sign-up details; a rejection needs a note; an approval is sent as decide', async () => {
  const request = { id: RID, created_at: '2026-11-03T02:00:00Z', customer_id: 'cust-9', customer_name: 'Sam Test',
    old: { first_name: 'Sam', last_name: 'Test', phone: '+61255500131', email: null, login_email: 'sam@example.com' },
    new: { phone: '+61255500132' }, signed_up_with: { name: 'Sam Test', phone: '+61255500131', email: 'sam@example.com' }, new_email_proven: false };
  const client = fakeSupabase({
    rpc: { affiliate_detail_change_requests: () => [request] },
    invoke: { 'affiliate-details': () => ({ data: { request_id: RID, status: 'applied' }, error: null }) },
  });
  globalThis.__supabase = client;
  await d.mount(h(mod.DetailChangeRequestsPanel)); await d.tick(5);
  const panel = document.querySelector('[data-panel="detail-changes"]');
  assert.match(panel.textContent, /Detail changes to check \(1\)/);
  assert.match(panel.textContent, /Phone\+61255500131\+61255500132/);
  assert.match(panel.textContent, /Signed up with: Sam Test · \+61255500131 · sam@example\.com/);
  await d.click(d.button('Reject', panel));
  assert.match(panel.querySelector('[role="alert"]')?.textContent ?? '', /give a reason/);
  assert.equal(client.calls.filter(c => c.fn).length, 0, 'nothing sent without a reason');
  await d.click(d.button('Approve', panel));
  assert.deepEqual(client.calls.filter(c => c.fn === 'affiliate-details').map(c => c.body), [{ action: 'decide', request_id: RID, approve: true, note: null }]);
});

test('Q7: the payout window says when the affiliate changed their phone', async () => {
  globalThis.__supabase = fakeSupabase({ rpc: { affiliate_self_phone_change: () => ({ changed_at: '2026-11-02T03:00:00Z', old_phone: '+61255500141', new_phone: '+61255500142' }) } });
  await d.mount(h(mod.SelfPhoneChangeNote, { customerId: 'cust-7' })); await d.tick(5);
  assert.match(document.querySelector('[data-note="self-phone-change"]')?.textContent ?? '', /changed their phone number themselves on 02\/11\/2026: \+61255500141 → \+61255500142\. Before paying by PayNow, check the number with them\./);
  globalThis.__supabase = fakeSupabase({ rpc: { affiliate_self_phone_change: () => null } });
  await d.mount(h(mod.SelfPhoneChangeNote, { customerId: 'cust-8' })); await d.tick(5);
  assert.equal(document.querySelector('[data-note="self-phone-change"]'), null);
});
