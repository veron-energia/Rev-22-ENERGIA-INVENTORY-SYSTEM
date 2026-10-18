// Users & Roles and the invitation form, rendered for real against a fake
// backend (429: ADMIN-AUTH-6, -7, -12, -15).
//
//   * a failed list says so, with Retry, instead of "No users yet";
//   * Resend and Cancel failures show on the page (they showed nowhere);
//   * an invitation whose set-up never finished is listed with Resend and
//     Cancel, and no Edit;
//   * the contact details are checked only when a save changes one of them,
//     so an Owner can switch off a Manager who has none on file; switching
//     someone off and promoting someone ask first; both windows ask before a
//     stray click throws away what was typed;
//   * the role list is the server's (Admin is no longer given), plus the
//     person's own role;
//   * the invitation form makes a new request id when the email, role or name
//     is corrected after a failure, and keeps it for a plain retry.
// Every name and address is made up.
//
// Run: node --test scripts/ui/tests/users-page.test.mjs
import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import { setupDom, bundle, fakeSupabase, driver } from '../page-harness.mjs';

const dom = setupDom();
const mod = await bundle(`
  import React from 'react';
  export { default as UsersPage } from './src/pages/UsersPage';
  export { InviteUserForm } from './src/components/users/InviteUserForm';
  export * as staffLogin from './src/lib/staffLogin';
  export { createRoot } from 'react-dom/client';
  export { act } from 'react';
  export { React };
`, { stubAuth: true });
const { UsersPage, InviteUserForm, staffLogin, React } = mod;
const d = driver(mod, dom);
after(async () => { await d.unmount(); dom.window.close(); });

const OWNER = { id: 'u-own', full_name: 'Olive Test', role: 'owner', is_active: true, email: 'olive@sig.invalid' };
const profiles = () => [
  OWNER,
  // A Manager with no contact details on file, as both Managers on production.
  { id: 'u-mgr', full_name: 'Mark Test', role: 'manager', is_active: true, email: 'mark@sig.invalid',
    work_phone: null, personal_phone: null, personal_email: null, invitation_status: 'accepted', deleted_at: null },
  { id: 'u-stf', full_name: 'Sara Test', role: 'staff', is_active: true, email: 'sara@sig.invalid',
    work_phone: '+61491573087', personal_phone: null, personal_email: null, invitation_status: 'accepted', deleted_at: null },
];
const adminRow = p => ({
  user_id: p.id, full_name: p.full_name, email: p.email, role: p.role, is_active: p.is_active,
  invitation_status: p.invitation_status ?? null, state: p.is_active ? 'active' : 'inactive',
  work_phone: p.work_phone ?? null, personal_phone: null, personal_email: null, store_ids: [], store_names: [],
  invitation_id: null, invited_at: null, invited_by_name: null, last_email_attempt_at: null, last_email_status: null,
  last_email_detail: null, resend_count: 0, cancelled_at: null, accepted_at: null, can_manage: p.id !== OWNER.id,
});
function backend(over = {}) {
  const tables = { profiles: profiles() };
  return fakeSupabase({
    tables,
    rpc: {
      user_admin_list: () => tables.profiles.map(adminRow),
      user_admin_orphan_invitations: () => [{
        invitation_id: '0000000a-0000-4000-8000-000000000001', email: 'nina@sig.invalid', full_name: 'Nina Test',
        role: 'staff', invited_at: '2026-10-08T02:00:00Z', last_email_status: 'failed',
      }],
      assignable_roles: () => ['owner', 'manager', 'inventory_manager', 'staff'],
      assignable_store_ids: () => [],
      ...over.rpc,
    },
    invoke: over.invoke ?? {},
    fail: over.fail ?? {},
  });
}
async function open(over) {
  globalThis.__supabase = backend(over);
  globalThis.__auth = { profile: OWNER };
  await d.mount(React.createElement(UsersPage));
  return globalThis.__supabase;
}
const rowOf = name => [...document.querySelectorAll('tr')].find(tr => tr.textContent.includes(name));
const asked = [];
dom.window.confirm = m => { asked.push(m); return globalThis.__answer ?? true; };

test('a list that cannot be read says so, with Retry, instead of "No users yet"', async () => {
  const sb = await open({ fail: { user_admin_list: 'permission denied for function user_admin_list' } });
  const alert = document.querySelector('[role="alert"]');
  assert.ok(alert && alert.textContent.includes('Could not load users: permission denied'), d.text());
  assert.ok(!d.text().includes('No users yet'));
  sb.fail.user_admin_list = undefined;
  await d.click(d.button('Retry'));
  assert.ok(rowOf('Mark Test'), 'Retry reads the list again');
});

test('an invitation that was never finished is listed, with Resend and Cancel and no Edit', async () => {
  await open();
  const row = rowOf('nina@sig.invalid');
  assert.ok(row, 'the unfinished invitation is listed');
  assert.ok(row.textContent.includes('Not set up yet. Use Resend to try again.'), 'it does not promise Resend will finish it');
  assert.ok(d.button('Resend', row) && d.button('Cancel', row));
  assert.equal(row.querySelector('button[aria-label^="Edit"]'), null, 'there is no profile to edit');
});

test('a Resend that fails says so on the page', async () => {
  const sb = await open({ invoke: { 'admin-invite-user': () => ({
    data: null,
    error: { context: new Response(JSON.stringify({ error: 'resend_failed', message: 'A new invitation link could not be created.' }), { status: 502 }) },
  }) } });
  await d.click(d.button('Resend', rowOf('nina@sig.invalid')));
  const alert = [...document.querySelectorAll('[role="alert"]')].find(a => a.textContent.includes('Could not resend'));
  assert.ok(alert, 'the failure shows on the page');
  assert.ok(alert.textContent.includes('A new invitation link could not be created.'));
  assert.ok(sb.calls.some(c => c.fn === 'admin-invite-user' && c.body?.action === 'resend'));
});

test('a Cancel that fails says so on the page', async () => {
  globalThis.__supabase = null;
  dom.window.prompt = () => 'not needed';
  await open({ invoke: { 'admin-invite-user': () => ({
    data: null, error: { context: new Response(JSON.stringify({ error: 'cancel_failed', message: 'This invitation is already cancelled.' }), { status: 400 }) },
  }) } });
  await d.click(d.button('Cancel', rowOf('nina@sig.invalid')));
  assert.ok([...document.querySelectorAll('[role="alert"]')].some(a => a.textContent.includes('This invitation is already cancelled.')));
});

test('an Owner switches off a Manager with no contact details on file: asked first, then saved', async () => {
  const sb = await open();
  await d.click(rowOf('Mark Test').querySelector('button[aria-label="Edit Mark Test"]'));
  const box = [...document.querySelectorAll('.modal input[type="checkbox"]')][0];
  await d.toggle(box);
  asked.length = 0;
  await d.click(d.button('Save', document.querySelector('.modal')));
  assert.ok(asked.some(q => q.startsWith('Switch Mark Test off?') && q.includes('signed out on every device')), asked.join('|'));
  assert.equal(document.querySelector('.modal'), null, 'saved and closed: the contact rule did not hold it up');
  const update = sb.calls.find(c => c.table === 'profiles' && c.op === 'update');
  assert.equal(update.payload.is_active, false);
  assert.ok(d.text().includes('signed out on every device'));
});

test('declining the question saves nothing', async () => {
  const sb = await open();
  await d.click(rowOf('Mark Test').querySelector('button[aria-label="Edit Mark Test"]'));
  await d.toggle([...document.querySelectorAll('.modal input[type="checkbox"]')][0]);
  globalThis.__answer = false;
  await d.click(d.button('Save', document.querySelector('.modal')));
  globalThis.__answer = undefined;
  assert.ok(document.querySelector('.modal'), 'still open');
  assert.equal(sb.calls.filter(c => c.table === 'profiles' && c.op === 'update').length, 0);
});

test('changing a contact detail still needs all three for Staff, Owners and Managers', async () => {
  const sb = await open();
  await d.click(rowOf('Sara Test').querySelector('button[aria-label="Edit Sara Test"]'));
  await d.setValue(d.labelled('Work Phone'), '+61491574118');
  await d.click(d.button('Save', document.querySelector('.modal')));
  assert.ok(document.querySelector('.modal [role="alert"]')?.textContent.includes('Personal phone is required for this role.'));
  assert.equal(sb.calls.filter(c => c.table === 'profiles' && c.op === 'update').length, 0);
});

test('the role list is the server\'s (no Admin), and a promotion to Manager asks first', async () => {
  const sb = await open();
  await d.click(rowOf('Sara Test').querySelector('button[aria-label="Edit Sara Test"]'));
  const select = d.labelled('Role');
  const options = [...select.querySelectorAll('option')].map(o => o.value);
  assert.deepEqual(options, ['owner', 'manager', 'inventory_manager', 'staff']);
  await d.setValue(select, 'manager');
  asked.length = 0;
  globalThis.__answer = false;
  await d.click(d.button('Save', document.querySelector('.modal')));
  globalThis.__answer = undefined;
  assert.ok(asked.some(q => q.startsWith('Make Sara Test a Manager?')), asked.join('|'));
  assert.equal(sb.calls.filter(c => c.table === 'profiles' && c.op === 'update').length, 0, 'declined: nothing saved');
});

test('both windows ask before a stray click outside throws away what was typed', async () => {
  await open();
  await d.click(rowOf('Sara Test').querySelector('button[aria-label="Edit Sara Test"]'));
  asked.length = 0;
  globalThis.__answer = false;
  await d.click(document.querySelector('.modal-overlay'));
  assert.ok(document.querySelector('.modal'), 'the Edit window stays');
  await d.click(d.button('Close', document.querySelector('.modal')));
  assert.ok(document.querySelector('.modal'), 'the X asks too');
  globalThis.__answer = undefined;
  await d.click(d.button('Cancel', document.querySelector('.modal')));
  await d.click(d.button('Invite User'));
  globalThis.__answer = false;
  await d.click(document.querySelector('.modal-overlay'));
  globalThis.__answer = undefined;
  assert.ok(document.querySelector('.modal')?.textContent.includes('Invite a User'), 'the Invite window stays');
  assert.ok(asked.length >= 3 && asked.every(q => q.startsWith('Discard what you have entered?')));
});

test('the invitation form renews its request id when the email is corrected after a failure', async () => {
  let n = 0;
  globalThis.__supabase = backend({ invoke: { 'admin-invite-user': () => {
    n++;
    return n === 1
      ? { data: null, error: { context: new Response(JSON.stringify({ error: 'email_in_use', message: 'That login email already belongs to a user in this system.' }), { status: 409 }) } }
      : { data: null, error: { context: new Response(JSON.stringify({ error: 'provisioning_failed', invitation_id: 'inv-x', message: 'The invitation is saved.' }), { status: 502 }) } };
  } } });
  let saved = 0;
  await d.mount(React.createElement(InviteUserForm, { onInvited() {}, onClose() {}, onSaved() { saved++; } }));
  await d.tick();
  await d.setValue(document.getElementById('inv-name'), 'Paula Test');
  await d.setValue(document.getElementById('inv-email'), 'paula@sig.invalid');
  await d.setValue(document.getElementById('inv-role'), 'inventory_manager');
  const form = document.querySelector('form');
  await d.submit(form);   // refused: the address is in use
  await d.submit(form);   // the same again: a retry keeps its id
  await d.setValue(document.getElementById('inv-email'), 'paula.two@sig.invalid');
  await d.submit(form);   // corrected: a new id
  const ids = globalThis.__supabase.calls.filter(c => c.fn === 'admin-invite-user').map(c => c.body.request_id);
  assert.equal(ids.length, 3);
  assert.equal(ids[0], ids[1], 'a plain retry keeps the request id (no second person)');
  assert.notEqual(ids[2], ids[1], 'a corrected email gets a new request id');
  assert.ok(saved >= 1, 'a saved but unfinished invitation refreshes the list');
  assert.ok(document.querySelector('[role="alert"]')?.textContent.includes('The invitation is saved.'));
});

test('the Owner\'s role list no longer says "These are the roles your own role can assign"', async () => {
  globalThis.__supabase = backend();
  await d.mount(React.createElement(InviteUserForm, { onInvited() {}, onClose() {} }));
  await d.tick();
  const options = [...document.getElementById('inv-role').querySelectorAll('option')].map(o => o.value).filter(Boolean);
  assert.deepEqual(options, ['owner', 'manager', 'inventory_manager', 'staff']);
  assert.ok(!d.text().includes('These are the roles your own role can assign'));
});

test('the wording helpers', () => {
  const { contactsChanged, contactRequired, deactivateQuestion, promotionQuestion } = staffLogin;
  assert.equal(contactsChanged({ work_phone: null }, { work_phone: '' }), false, 'blank and missing are the same');
  assert.equal(contactsChanged({ work_phone: ' 8123 ' }, { work_phone: '8123' }), false, 'outer spaces do not count');
  assert.equal(contactsChanged({ personal_email: null }, { personal_email: 'a@b.c' }), true);
  assert.deepEqual(['staff', 'owner', 'manager', 'admin', 'inventory_manager'].map(contactRequired), [true, true, true, false, false]);
  assert.match(deactivateQuestion('Mark Test'), /^Switch Mark Test off\?/);
  assert.match(promotionQuestion('Sara Test', 'staff', 'owner'), /^Make Sara Test an Owner\?/);
  assert.match(promotionQuestion('Sara Test', 'inventory_manager', 'manager'), /^Make Sara Test a Manager\?/);
  assert.equal(promotionQuestion('Olive Test', 'owner', 'manager'), null, 'a step down is not a promotion');
  assert.equal(promotionQuestion('Sara Test', 'staff', 'inventory_manager'), null);
  assert.equal(promotionQuestion('Sara Test', 'staff', 'staff'), null);
});
