// Behaviour tests for Health Surveys → To match (433): the QR forms the server
// held for staff instead of making a second customer.
//
//   - each form shows what was typed, why it waits, and per customer which of
//     phone, email and name match, and any survey they already have;
//   - Attach is refused (disabled) for a customer with a survey or retired;
//   - Attach needs a note; Attach to another customer needs a customer too;
//   - New customer needs no note; Close is offered to an Owner or Manager
//     only, and needs a reason;
//   - each sends the server exactly what it needs, shows the server's refusal
//     in the window, and on success says what happened and reloads;
//   - 468: the reason in plain words from who has the phone and the email now;
//     where several customers have both, Delete (the Customers page's own,
//     the name typed to confirm) for an Owner or Manager only, on those.
//   - 468 (A): a form whose one customer with the phone and the email already
//     has a survey waits with its own reason; (D) namesakes and a customer of
//     another name with both: no Delete.
//
// These are JSDOM tests with the database stubbed; invented data only.
// Run: node --test scripts/survey/tests/survey-holds-panel.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { mkdtemp } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { build } from 'esbuild';
import { JSDOM } from 'jsdom';

const dom = new JSDOM('<!doctype html><html><body></body></html>', { url: 'https://example.test/surveys' });
globalThis.window = dom.window;
globalThis.document = dom.window.document;
globalThis.IS_REACT_ACT_ENVIRONMENT = true;
dom.window.requestAnimationFrame = fn => setTimeout(() => fn(Date.now()), 0);
globalThis.requestAnimationFrame = dom.window.requestAnimationFrame;
if (!globalThis.navigator) globalThis.navigator = dom.window.navigator;

const React = (await import('react')).default;
const { act } = await import('react');
const { createRoot } = await import('react-dom/client');
const { Simulate } = await import('react-dom/test-utils');

const require = createRequire(import.meta.url);
const dir = await mkdtemp(join(tmpdir(), 'energia-survey-holds-'));

const STUBS = {
  sb: 'export const supabase = new Proxy({}, { get: (_t, p) => globalThis.__SB__[p] });',
  auth: 'export const useAuth = () => ({ profile: { id: "u-1", role: "staff" } });',
  types: 'export {};',
  search: `
    import React from 'react';
    export const CustomerSearchSelect = (p) => React.createElement('input', {
      id: 'stub-customer', value: p.value, onChange: e => p.onChange(e.target.value) });`,
  lucide: `
    import React from 'react';
    const Icon = () => React.createElement('span', { 'aria-hidden': 'true' });
    export const ClipboardList = Icon, Link2 = Icon, UserPlus = Icon, XCircle = Icon, Lock = Icon;`,
};

await build({
  entryPoints: ['src/components/SurveyHoldsPanel.tsx'],
  outfile: join(dir, 'panel.mjs'),
  bundle: true, format: 'esm', platform: 'node', jsx: 'automatic',
  plugins: [{
    name: 'stubs',
    setup(b) {
      b.onResolve({ filter: /^react(?:\/.*)?$/ }, a => ({ path: require.resolve(a.path), external: true }));
      b.onResolve({ filter: /^react-dom(?:\/.*)?$/ }, a => ({ path: require.resolve(a.path), external: true }));
      b.onResolve({ filter: /^lucide-react$/ }, () => ({ path: 'lucide', namespace: 's' }));
      b.onResolve({ filter: /\/lib\/supabase$/ }, () => ({ path: 'sb', namespace: 's' }));
      b.onResolve({ filter: /\/context\/AuthContext$/ }, () => ({ path: 'auth', namespace: 's' }));
      b.onResolve({ filter: /\/types$/ }, () => ({ path: 'types', namespace: 's' }));
      b.onResolve({ filter: /\/SearchSelect$/ }, () => ({ path: 'search', namespace: 's' }));
      b.onLoad({ filter: /.*/, namespace: 's' }, a => ({ contents: STUBS[a.path], loader: 'jsx' }));
    },
  }],
});
const { default: SurveyHoldsPanel } = await import(pathToFileURL(join(dir, 'panel.mjs')).href);

const cand = (id, name, flags, survey_no = null, deleted = false) => ({
  customer_id: id, full_name: name, phone: '+6584330901', email: `${id}@sig.invalid`, date_of_birth: '1961-04-02',
  created_at: '2026-07-27T02:00:00Z', deleted, phone_matches: !!flags.phone, email_matches: !!flags.email,
  name_matches: !!flags.name, survey_no,
});
const FORMS = [
  { survey_id: 'hs-1', survey_no: 'HS-20261016-a1b2c3', submitted_at: '2026-10-16T02:15:00Z', store_name: 'Fixture Store',
    event_name: null, full_name: 'Ah Kow Testkoh', date_of_birth: '1988-03-14', sex: 'male', phone: '+6584330901',
    email: 'ahkow@sig.invalid', occupation: 'Engineer', source_label: 'Walk-in', reason: 'phone_in_use',
    held_at: '2026-10-16T02:15:00Z', candidates: [cand('c-bee', 'Bee Hoon Testkoh', { phone: true })] },
  { survey_id: 'hs-2', survey_no: 'HS-20261016-99ab01', submitted_at: '2026-10-16T06:30:00Z', store_name: 'Fixture Store',
    event_name: 'Roadshow', full_name: 'Qi Pei Testng', date_of_birth: null, sex: 'female', phone: '+6584330904',
    email: 'qipei@sig.invalid', occupation: null, source_label: null, reason: 'several_name_matches',
    held_at: '2026-10-16T06:30:00Z',
    candidates: [cand('c-p1', 'Pei Qi Testng', { phone: true, name: true }),
                 cand('c-p2', 'Testng Pei Qi', { phone: true, name: true }, 'HS-20260901-77aa00'),
                 cand('c-p3', 'Pei Qi (old) Testng', { phone: true, name: true }, null, true)] },
];

async function mount({ canClose = false, canDelete = false, reply = () => ({ data: { ok: true }, error: null }), forms = FORMS } = {}) {
  const calls = [];
  let changed = 0;
  globalThis.__SB__ = { rpc: async (name, args) => { calls.push({ name, args }); return reply(name, args); } };
  const node = document.createElement('div');
  document.body.appendChild(node);
  const root = createRoot(node);
  await act(async () => {
    root.render(React.createElement(SurveyHoldsPanel, { forms, canClose, canDelete, onChanged: () => { changed += 1; } }));
  });
  const $ = sel => document.querySelector(sel);
  return {
    calls, changed: () => changed, $,
    text: () => document.body.textContent,
    async click(sel) {
      const el = $(sel); assert.ok(el, `no element ${sel}`);
      await act(async () => { Simulate.click(el); });
      await act(async () => { await new Promise(r => setTimeout(r, 5)); });
    },
    async type(sel, value) { await act(async () => { Simulate.change($(sel), { target: { value } }); }); },
    close() { act(() => root.unmount()); node.remove(); },
  };
}

test('each form shows what was typed, why it waits, and what matches', async () => {
  const ui = await mount();
  try {
    const t = ui.text();
    assert.match(t, /HS-20261016-a1b2c3/);
    assert.match(t, /Ah Kow Testkoh/);
    assert.match(t, /Its phone number belongs to a customer under another name\./);
    assert.match(t, /When it was sent, its name matched more than one customer with this phone number\./);
    assert.match(t, /14\/03\/1988/);
    assert.match(t, /Engineer/);
    assert.match(t, /Bee Hoon Testkoh/);
    assert.match(t, /HS-20260901-77aa00/);
    assert.match(t, /Retired/);
  } finally { ui.close(); }
});

test('Attach is disabled for a customer with a survey or a retired one', async () => {
  const ui = await mount();
  try {
    assert.equal(ui.$('[data-attach="c-p1"]').disabled, false);
    assert.equal(ui.$('[data-attach="c-p2"]').disabled, true);
    assert.match(ui.$('[data-attach="c-p2"]').title, /already has a survey \(HS-20260901-77aa00\)/);
    assert.equal(ui.$('[data-attach="c-p3"]').disabled, true);
  } finally { ui.close(); }
});

test('Close is offered to an Owner or Manager only', async () => {
  const staff = await mount({ canClose: false });
  try { assert.equal(staff.$('[data-close]'), null); } finally { staff.close(); }
  const owner = await mount({ canClose: true });
  try { assert.ok(owner.$('[data-close="hs-1"]')); } finally { owner.close(); }
});

test('Attach needs a note, then sends the form, the customer and the note', async () => {
  const ui = await mount();
  try {
    await ui.click('[data-attach="c-bee"]');
    assert.equal(ui.$('[data-confirm]').disabled, true);
    await ui.type('textarea[data-note]', '   ');
    assert.equal(ui.$('[data-confirm]').disabled, true);
    await ui.type('textarea[data-note]', ' Checked her NRIC ');
    assert.equal(ui.$('[data-confirm]').disabled, false);
    await ui.click('[data-confirm]');
    assert.deepEqual(ui.calls.at(-1), { name: 'attach_held_health_survey',
      args: { p_survey_id: 'hs-1', p_customer_id: 'c-bee', p_note: 'Checked her NRIC' } });
    assert.equal(ui.changed(), 1);
    assert.match(ui.text(), /HS-20261016-a1b2c3 is now Bee Hoon Testkoh's survey\./);
    assert.equal(ui.$('[data-confirm]'), null);
  } finally { ui.close(); }
});

test('Attach to another customer needs the customer and the note', async () => {
  const ui = await mount();
  try {
    await ui.click('[data-other="hs-1"]');
    await ui.type('textarea[data-note]', 'Same inbox; she confirmed');
    assert.equal(ui.$('[data-confirm]').disabled, true);
    await ui.type('#stub-customer', 'c-other');
    assert.equal(ui.$('[data-confirm]').disabled, false);
    await ui.click('[data-confirm]');
    assert.deepEqual(ui.calls.at(-1).args, { p_survey_id: 'hs-1', p_customer_id: 'c-other', p_note: 'Same inbox; she confirmed' });
    assert.match(ui.text(), /is now attached to the customer you chose\./);
  } finally { ui.close(); }
});

test('New customer needs no note; an empty note is sent as none', async () => {
  const ui = await mount();
  try {
    await ui.click('[data-create="hs-1"]');
    assert.equal(ui.$('[data-confirm]').disabled, false);
    await ui.click('[data-confirm]');
    assert.deepEqual(ui.calls.at(-1), { name: 'create_customer_from_held_survey', args: { p_survey_id: 'hs-1', p_note: null } });
    assert.match(ui.text(), /A new customer was made from HS-20261016-a1b2c3, and the form is theirs\./);
  } finally { ui.close(); }
});

test('Close needs a reason', async () => {
  const ui = await mount({ canClose: true });
  try {
    await ui.click('[data-close="hs-2"]');
    assert.equal(ui.$('[data-confirm]').disabled, true);
    await ui.type('textarea[data-note]', 'Sent twice');
    await ui.click('[data-confirm]');
    assert.deepEqual(ui.calls.at(-1), { name: 'close_held_health_survey', args: { p_survey_id: 'hs-2', p_reason: 'Sent twice' } });
    assert.match(ui.text(), /HS-20261016-99ab01 was closed without a customer\./);
  } finally { ui.close(); }
});

test("the server's refusal shows in the window, in words staff can act on, and nothing reloads", async () => {
  const ui = await mount({ reply: () => ({ data: null, error: { message: 'CUSTOMER_PHONE_LIMIT: This phone number already belongs to 3 non-deleted customers across Energia. Enter a different valid number.' } }) });
  try {
    await ui.click('[data-create="hs-1"]');
    await ui.click('[data-confirm]');
    assert.match(ui.$('[role=alert]').textContent, /already belongs to 3 customers, so no new customer can be made with it/);
    assert.doesNotMatch(ui.$('[role=alert]').textContent, /Enter a different valid number/);
    assert.ok(ui.$('[data-confirm]'), 'the window stays open');
    assert.equal(ui.changed(), 0);
  } finally { ui.close(); }
});

test('a form someone else dealt with meanwhile: the message shows and the list reloads', async () => {
  const ui = await mount({ reply: () => ({ data: null, error: { message: 'This form has already been dealt with.' } }) });
  try {
    await ui.click('[data-attach="c-bee"]');
    await ui.type('textarea[data-note]', 'Checked');
    await ui.click('[data-confirm]');
    assert.match(ui.$('[role=alert]').textContent, /already been dealt with/);
    assert.equal(ui.changed(), 1);
  } finally { ui.close(); }
});

test('the last success message clears when the next action opens', async () => {
  const ui = await mount();
  try {
    await ui.click('[data-create="hs-1"]');
    await ui.click('[data-confirm]');
    assert.match(ui.text(), /A new customer was made from/);
    await ui.click('[data-other="hs-2"]');
    assert.doesNotMatch(ui.text(), /A new customer was made from/);
  } finally { ui.close(); }
});

// ── 419 (Q10) ───────────────────────────────────────────────────────────
// A customer whose survey is a consultant's record they have not signed can
// take a held form: its answers go into that record.
const TAKES = [{
  ...FORMS[0], survey_id: 'hs-9', survey_no: 'HS-20261018-q10000', full_name: 'Faye Testsix', phone: '+61491578148',
  candidates: [{ ...cand('c-fay', 'Fay Testsix', { phone: true }, 'HS-20261001-cons01'), phone: '+61491578148',
                 survey_takes_form: true },
               { ...cand('c-esme', 'Esme Testfive', { email: true }, 'HS-20261001-sign01'), phone: '+61491578888',
                 survey_takes_form: false }],
}];

test('419 (Q10): a customer with an unsigned consultant survey can take the form; a signed survey still blocks', async () => {
  const ui = await mount({ forms: TAKES, reply: () => ({ data: { ok: true, survey_no: 'HS-20261018-q10000',
                                                                  signed_into_survey_no: 'HS-20261001-cons01' }, error: null }) });
  try {
    assert.equal(ui.$('[data-attach="c-fay"]').disabled, false);
    assert.match(ui.text(), /Not signed yet: the form's answers go into it/);
    assert.equal(ui.$('[data-attach="c-esme"]').disabled, true);
    await ui.click('[data-attach="c-fay"]');
    assert.ok(ui.$('[data-takes-form]'), 'the window says the answers go into her survey');
    await ui.type('[data-note]', 'Checked her IC');
    await ui.click('[data-confirm]');
    assert.equal(ui.calls[0].name, 'attach_held_health_survey');
    assert.match(ui.text(), /The answers on HS-20261018-q10000 went into Fay Testsix's survey HS-20261001-cons01, which is now signed\./);
  } finally { ui.close(); }
});

// ── 468 ─────────────────────────────────────────────────────────────────
// The Owner, 24 Oct 2026: a form whose phone and email are ONE customer's is
// attached by the server at once; one whose phone and email several customers
// have waits here, with Delete on each of them for an Owner or Manager (the
// Customers page's own delete, the name typed to confirm). The reason is said
// in plain words from who has the phone and the email now.
const DUPS = [{
  ...FORMS[0], survey_id: 'hs-d', survey_no: 'HS-20261024-d00001', full_name: 'Jody Testdup', reason: 'phone_and_email_in_use',
  candidates: [cand('c-jo1', 'Jo Testdup', { phone: true, email: true }),
               cand('c-jo2', 'Joanne Testdup', { phone: true, email: true }, 'HS-20261001-jo2000'),
               cand('c-kin', 'Kin Testdup', { phone: true })],
}];
const SPLIT = [{
  ...FORMS[0], survey_id: 'hs-s', survey_no: 'HS-20261024-s00001', reason: 'phone_and_email_in_use',
  candidates: [cand('c-ph', 'Phone Testsplit', { phone: true }), cand('c-em', 'Mail Testsplit', { email: true })],
}];
const AFTER_DELETE = [{ ...DUPS[0], candidates: [DUPS[0].candidates[0], { ...DUPS[0].candidates[1], deleted: true }, DUPS[0].candidates[2]] }];
const NAMESAKES = [{
  ...FORMS[1], survey_id: 'hs-n', reason: 'several_name_matches',
  candidates: [cand('c-g1', 'Gus Testmany', { phone: true, email: true, name: true }),
               cand('c-g2', 'Gus Testmany', { phone: true, email: true, name: true })],
}];

test('468: several customers with the phone and the email: the reason says so, and only an Owner or Manager gets Delete, on those two only', async () => {
  const staff = await mount({ forms: DUPS, canClose: false });
  try {
    assert.match(staff.$('[data-hold="hs-d"] [data-reason]').textContent, /^More than one customer has this phone number and this email\./);
    assert.match(staff.text(), /an Owner or Manager can delete it here/);
    assert.equal(staff.$('[data-delete]'), null, 'staff get no Delete');
  } finally { staff.close(); }
  const owner = await mount({ forms: DUPS, canClose: true, canDelete: true });
  try {
    assert.ok(owner.$('[data-delete="c-jo1"]') && owner.$('[data-delete="c-jo2"]'), 'Delete on both with the phone and the email');
    assert.equal(owner.$('[data-delete="c-kin"]'), null, 'not on the customer with the phone only');
    assert.match(owner.text(), /delete it, then attach the form to the one kept/);
  } finally { owner.close(); }
});

test('468: Delete is the Customers page\'s own: the name typed to confirm, a reason, delete_customer; then the list reloads and the form still waits', async () => {
  const ui = await mount({ forms: DUPS, canClose: true, canDelete: true,
                           reply: () => ({ data: { success: true, full_name: 'Joanne Testdup' }, error: null }) });
  try {
    await ui.click('[data-delete="c-jo2"]');
    assert.match(ui.$('[data-delete-intro]').textContent, /same phone number and email as another customer/);
    assert.match(ui.$('[data-delete-intro]').textContent, /has a health survey \(HS-20261001-jo2000\); it stays with the deleted record/);
    assert.equal(ui.$('[data-confirm-delete]').disabled, true, 'nothing typed yet');
    await ui.type('[data-delete-name]', 'Jo Testdup');
    assert.equal(ui.$('[data-confirm-delete]').disabled, true, 'another customer\'s name');
    assert.match(ui.text(), /That does not match the customer's name\./);
    await ui.type('[data-delete-name]', '  joanne   TESTDUP ');
    await ui.type('[data-delete-reason]', ' Duplicate of Jo ');
    assert.equal(ui.$('[data-confirm-delete]').disabled, false);
    await ui.click('[data-confirm-delete]');
    assert.deepEqual(ui.calls.at(-1), { name: 'delete_customer',
      args: { p_customer_id: 'c-jo2', p_confirm_name: '  joanne   TESTDUP ', p_reason: 'Duplicate of Jo' } });
    assert.equal(ui.calls.filter(c => c.name !== 'delete_customer').length, 0, 'nothing else is sent: the form is not attached');
    assert.equal(ui.changed(), 1, 'the list reloads');
    assert.equal(ui.$('[data-confirm-delete]'), null, 'the window closes');
    assert.match(ui.text(), /Joanne Testdup was deleted\. HS-20261024-d00001 still waits: attach it to the customer it belongs to\./);
    const status = [...document.querySelectorAll('[role=status]')];
    assert.equal(status.length, 1, 'one message');
    assert.equal(status[0].closest('[data-hold]')?.dataset.hold, 'hs-d', 'the message shows in the form\'s own card, by its customers');
  } finally { ui.close(); }
});

test('468: the one kept already has a survey: the message after a delete says so and points to Close, not Attach', async () => {
  const ui = await mount({ forms: DUPS, canClose: true, canDelete: true,
                           reply: () => ({ data: { success: true, full_name: 'Jo Testdup' }, error: null }) });
  try {
    await ui.click('[data-delete="c-jo1"]');
    await ui.type('[data-delete-name]', 'Jo Testdup');
    await ui.click('[data-confirm-delete]');
    assert.match(ui.text(), /Jo Testdup was deleted\. HS-20261024-d00001 still waits, but Joanne Testdup already has a survey and a customer can have only one: if the form is theirs, close it without attaching it\./);
    assert.doesNotMatch(ui.text(), /attach it to the customer it belongs to/);
  } finally { ui.close(); }
});

test('468: the delete window\'s boxes are named by their labels', async () => {
  const ui = await mount({ forms: DUPS, canClose: true, canDelete: true });
  try {
    await ui.click('[data-delete="c-jo2"]');
    const name = ui.$('[data-delete-name]'), reason = ui.$('[data-delete-reason]');
    assert.ok(name.id && reason.id && name.id !== reason.id);
    assert.match(document.querySelector(`label[for="${name.id}"]`).textContent, /^Type Joanne Testdup to confirm \*$/);
    assert.equal(document.querySelector(`label[for="${reason.id}"]`).textContent, 'Reason');
  } finally { ui.close(); }
});

test('468: each Attach and Delete button names its customer for a screen reader', async () => {
  const ui = await mount({ forms: DUPS, canClose: true, canDelete: true });
  try {
    assert.deepEqual([...document.querySelectorAll('[data-delete]')].map(b => b.getAttribute('aria-label')),
      ['Delete Jo Testdup', 'Delete Joanne Testdup (HS-20261001-jo2000)']);
    assert.deepEqual([...document.querySelectorAll('[data-attach]')].map(b => b.getAttribute('aria-label')),
      ['Attach HS-20261024-d00001 to Jo Testdup', 'Attach HS-20261024-d00001 to Joanne Testdup', 'Attach HS-20261024-d00001 to Kin Testdup']);
  } finally { ui.close(); }
});

test('468: a refused delete shows the server\'s words in the window, and nothing reloads', async () => {
  const ui = await mount({ forms: DUPS, canClose: true, canDelete: true,
                           reply: () => ({ data: null, error: { message: 'This customer still holds S$20.00 of wallet credit. Refund or transfer it first.' } }) });
  try {
    await ui.click('[data-delete="c-jo1"]');
    await ui.type('[data-delete-name]', 'Jo Testdup');
    await ui.click('[data-confirm-delete]');
    assert.match(ui.$('[role=alert]').textContent, /still holds S\$20\.00 of wallet credit/);
    assert.ok(ui.$('[data-confirm-delete]'), 'the window stays open');
    assert.equal(ui.changed(), 0);
  } finally { ui.close(); }
});

test('468: once one is deleted, the other is the only one left: no more Delete, and the reason says so', async () => {
  const ui = await mount({ forms: AFTER_DELETE, canClose: true, canDelete: true });
  try {
    assert.equal(ui.$('[data-delete]'), null);
    assert.match(ui.$('[data-reason]').textContent, /^One customer has this phone number and this email, under another name\./);
    assert.equal(ui.$('[data-attach="c-jo2"]').disabled, true, 'the deleted record cannot take the form');
    assert.equal(ui.$('[data-attach="c-jo1"]').disabled, false);
  } finally { ui.close(); }
});

test('468: the phone one customer\'s and the email another\'s: said so, and no Delete even for an Owner', async () => {
  const ui = await mount({ forms: SPLIT, canClose: true, canDelete: true });
  try {
    assert.match(ui.$('[data-reason]').textContent, /^When it was sent, its phone number and its email were on file under other names\.$/);
    assert.equal(ui.$('[data-delete]'), null);
    assert.equal(ui.$('[data-duplicate-note]'), null);
  } finally { ui.close(); }
});

test('468: both duplicates since deleted: the reason says how it was when sent, and no Delete is left', async () => {
  const BOTH_GONE = [{ ...DUPS[0], candidates: DUPS[0].candidates.map(c => ({ ...c, deleted: c.email_matches })) }];
  const ui = await mount({ forms: BOTH_GONE, canClose: true, canDelete: true });
  try {
    assert.match(ui.$('[data-reason]').textContent, /^When it was sent, its phone number and its email were on file under other names\.$/);
    assert.equal(ui.$('[data-delete]'), null);
    assert.equal(ui.$('[data-duplicate-note]'), null);
  } finally { ui.close(); }
});

test('468: namesakes on the phone that both have the email: the reason adds it, and an Owner gets Delete on both', async () => {
  const ui = await mount({ forms: NAMESAKES, canClose: true, canDelete: true });
  try {
    assert.match(ui.$('[data-reason]').textContent,
      /^When it was sent, its name matched more than one customer with this phone number\. More than one customer below has both this phone number and this email\./);
    assert.ok(ui.$('[data-delete="c-g1"]') && ui.$('[data-delete="c-g2"]'));
  } finally { ui.close(); }
});

test('468: namesakes on the phone, one with the email, and a customer of another name with both: Delete on the two with both only', async () => {
  const MIXED = [{
    ...FORMS[1], survey_id: 'hs-m', reason: 'several_name_matches',
    candidates: [cand('c-f1', 'Fae Testboth', { phone: true, email: true, name: true }),
                 cand('c-f2', 'Fae Testboth', { phone: true, name: true }),
                 cand('c-z', 'Zed Testboth', { phone: true, email: true })],
  }];
  const ui = await mount({ forms: MIXED, canClose: true, canDelete: true });
  try {
    assert.match(ui.$('[data-reason]').textContent, /More than one customer below has both this phone number and this email\./);
    assert.ok(ui.$('[data-delete="c-f1"]') && ui.$('[data-delete="c-z"]'));
    assert.equal(ui.$('[data-delete="c-f2"]'), null);
  } finally { ui.close(); }
});

// 468 (the Owner, 24 Oct 2026, A): a form found only by the phone and the
// email, whose customer already has a survey, waits quietly here.
const HAS_SURVEY = [{
  ...FORMS[0], survey_id: 'hs-a', survey_no: 'HS-20261024-a00001', full_name: 'Pippa Testsurvey',
  reason: 'phone_and_email_customer_has_survey',
  candidates: [cand('c-pia', 'Pia Testsurvey', { phone: true, email: true }, 'HS-20261001-pia000')],
}];

test('468 (A): a form for the one customer with the phone and the email, who has a survey: the reason in plain words, Attach refused, New customer offered', async () => {
  const staff = await mount({ forms: HAS_SURVEY, canClose: false });
  try {
    assert.equal(staff.$('[data-hold="hs-a"] [data-reason]').textContent,
      'Its phone number and email are a customer\'s, under another name, and that customer already has a health survey, '
      + 'so it was not attached. If it is someone else (for example a family member sharing them), make a new customer '
      + 'from it; if it is the same person, an Owner or Manager can close it.');
    assert.equal(staff.$('[data-attach="c-pia"]').disabled, true, 'a customer has only one survey');
    assert.match(staff.$('[data-attach="c-pia"]').title, /already has a survey \(HS-20261001-pia000\)/);
    assert.ok(staff.$('[data-create="hs-a"]'), 'any staff may make a new customer from it');
    assert.equal(staff.$('[data-close]'), null, 'staff do not close it');
    assert.equal(staff.$('[data-delete]'), null, 'one customer with both: no Delete');
    assert.equal(staff.$('[data-duplicate-note]'), null);
    assert.match(staff.text(), /unless that customer\s+already has a health survey: then it waits here too/);
    await staff.click('[data-create="hs-a"]');
    await staff.click('[data-confirm]');
    assert.deepEqual(staff.calls.at(-1), { name: 'create_customer_from_held_survey', args: { p_survey_id: 'hs-a', p_note: null } });
  } finally { staff.close(); }
  const owner = await mount({ forms: HAS_SURVEY, canClose: true, canDelete: true });
  try {
    assert.ok(owner.$('[data-close="hs-a"]'), 'an Owner or Manager may close it');
    assert.equal(owner.$('[data-delete]'), null);
  } finally { owner.close(); }
});

test('468 (D): two namesakes on the phone and one customer of another name with the phone and the email: it waits for the namesakes, no Delete', async () => {
  const D = [{
    ...FORMS[1], survey_id: 'hs-h', reason: 'several_name_matches',
    candidates: [cand('c-h1', 'Hal Testother', { phone: true, name: true }),
                 cand('c-h2', 'Hal Testother', { phone: true, name: true }),
                 cand('c-ida', 'Ida Testother', { phone: true, email: true })],
  }];
  const ui = await mount({ forms: D, canClose: true, canDelete: true });
  try {
    assert.equal(ui.$('[data-reason]').textContent, 'When it was sent, its name matched more than one customer with this phone number.');
    assert.equal(ui.$('[data-delete]'), null, 'one customer with both is no duplicate');
    assert.equal(ui.$('[data-attach="c-ida"]').disabled, false, 'staff may still attach it to her');
  } finally { ui.close(); }
});
