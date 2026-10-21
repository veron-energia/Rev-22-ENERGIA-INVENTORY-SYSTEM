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
//     in the window, and on success says what happened and reloads.
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

async function mount({ canClose = false, reply = () => ({ data: { ok: true }, error: null }), forms = FORMS } = {}) {
  const calls = [];
  let changed = 0;
  globalThis.__SB__ = { rpc: async (name, args) => { calls.push({ name, args }); return reply(name, args); } };
  const node = document.createElement('div');
  document.body.appendChild(node);
  const root = createRoot(node);
  await act(async () => {
    root.render(React.createElement(SurveyHoldsPanel, { forms, canClose, onChanged: () => { changed += 1; } }));
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
    assert.match(t, /Its name matches more than one customer with this phone number\./);
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
