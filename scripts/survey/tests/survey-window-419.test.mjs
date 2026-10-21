// 419: the health survey window (SurveyDetailModal).
//
//   - Edit details starts from what is stored, with Yes / No / Not answered,
//     and sends only what changed to update_survey_particulars_v2
//     (CUSTOMERS-4); a filled-in date of birth is an Owner's or Manager's to
//     change, with a reason (Q9).
//   - Save Review is off until the boxes differ from the saved review; after
//     a save the boxes show what was saved; emptied boxes do not replace it
//     (CUSTOMERS-K1).
//   - Start survey makes nothing on opening; the first save makes the survey,
//     at the store chosen when the person has more than one (CUSTOMERS-5, M1).
//   - A survey that cannot be opened says why; the signed PDF of another
//     store is explained, not offered (CUSTOMERS-14); Sex shows Other.
//
// JSDOM tests with the database stubbed; invented data only.
// Run: node --test scripts/survey/tests/survey-window-419.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { build } from 'esbuild';
import { JSDOM } from 'jsdom';

const dom = new JSDOM('<!doctype html><html><body></body></html>', { url: 'https://example.test/surveys' });
globalThis.window = dom.window;
globalThis.document = dom.window.document;
globalThis.IS_REACT_ACT_ENVIRONMENT = true;
if (!globalThis.navigator) globalThis.navigator = dom.window.navigator;

const React = (await import('react')).default;
const { act } = await import('react');
const { createRoot } = await import('react-dom/client');
const { Simulate } = await import('react-dom/test-utils');

const require = createRequire(import.meta.url);
const dir = await mkdtemp(join(tmpdir(), 'energia-survey-window-'));

const STUBS = {
  sb: 'export const supabase = new Proxy({}, { get: (_t, p) => globalThis.__SB__[p] });',
  auth: 'export const useAuth = () => ({ profile: { id: "u-1", role: globalThis.__ROLE__ } });',
  types: `export const isOwnerOrManager = r => r === 'owner' || r === 'manager';`,
  ui: `import React from 'react';
    export const Modal = ({ title, children, footer }) =>
      React.createElement('div', { role: 'dialog' }, React.createElement('h1', null, title), children,
                          React.createElement('footer', null, footer));`,
  phone: `import React from 'react';
    export default function PhoneInput(p) {
      return React.createElement('input', { 'data-phone': true, value: p.value || '', onChange: e => p.onChange(e.target.value, true) });
    }`,
  files: `import React from 'react';
    export default function Files(p) {
      return React.createElement('button', { 'data-add-file': true, onClick: async () => {
        globalThis.__FILE_TARGET__ = p.surveyId ? { surveyId: p.surveyId } : await p.getTarget();
      } }, 'add file');
    }`,
  lucide: `import React from 'react';
    const Icon = () => React.createElement('span', { 'aria-hidden': 'true' });
    export const Download = Icon, RefreshCw = Icon, FileText = Icon, Check = Icon;`,
};

await build({
  entryPoints: ['src/components/SurveyDetailModal.tsx'],
  outfile: join(dir, 'modal.mjs'),
  bundle: true, format: 'esm', platform: 'node', jsx: 'automatic', logLevel: 'silent',
  plugins: [{
    name: 'stubs',
    setup(b) {
      b.onResolve({ filter: /^react(?:\/.*)?$/ }, a => ({ path: require.resolve(a.path), external: true }));
      b.onResolve({ filter: /^react-dom(?:\/.*)?$/ }, a => ({ path: require.resolve(a.path), external: true }));
      b.onResolve({ filter: /^lucide-react$/ }, () => ({ path: 'lucide', namespace: 's' }));
      b.onResolve({ filter: /\/lib\/supabase$/ }, () => ({ path: 'sb', namespace: 's' }));
      b.onResolve({ filter: /\/context\/AuthContext$/ }, () => ({ path: 'auth', namespace: 's' }));
      b.onResolve({ filter: /\/types$/ }, () => ({ path: 'types', namespace: 's' }));
      b.onResolve({ filter: /^\.\/ui$/ }, () => ({ path: 'ui', namespace: 's' }));
      b.onResolve({ filter: /\/PhoneInput$/ }, () => ({ path: 'phone', namespace: 's' }));
      b.onResolve({ filter: /\/SurveyAttachments$/ }, () => ({ path: 'files', namespace: 's' }));
      b.onLoad({ filter: /.*/, namespace: 's' }, a => ({ contents: STUBS[a.path], loader: 'jsx' }));
    },
  }],
});
const { default: SurveyDetailModal } = await import(pathToFileURL(join(dir, 'modal.mjs')).href);

const SURVEY = () => ({
  id: 'hs-1', survey_no: 'HS-20261018-aaaaaa', customer_id: 'c-1', store_id: 'st-a', full_name: 'Bea Testtwo',
  first_name: 'Bea', last_name: 'Testtwo', phone: '+61491570157', email: 'bea@example.com',
  date_of_birth: '1981-05-06', age: 45, sex: 'other', occupation: null, others_text: null,
  source_option_id: null, source_label: null, source_details: null, event_name: null,
  has_medical_condition: null, drinks_alcohol: false, smokes: null, on_treatment: null, treatment_list: null,
  consent_newsletter_email: false, consent_marketing_email: false, consent_marketing_sms: false,
  consent_marketing_phone: false, signature_data: null, signed_date: null, submitted_at: '2026-10-01T02:00:00Z',
  acidity_result: 'green', health_goals: 'Sleep', remarks_condition: 'Tight back', remarks_recommendation: null,
  reviewed_at: '2026-10-02T02:00:00Z',
});

/** The database, stubbed: health_survey_detail answers state.survey; every call is kept. */
function makeDb({ survey = SURVEY(), detailError = null, customer = { id: 'c-1', date_of_birth: '1981-05-06' }, extra = {}, v2Error = null } = {}) {
  const state = { survey, calls: [], customer };
  const chain = table => {
    const c = {
      select: () => c, order: () => c, eq: () => c, is: () => c,
      maybeSingle: async () => ({ data: table === 'customers' ? state.customer : null, error: null }),
      then: (res, rej) => Promise.resolve({ data: [] }).then(res, rej),
    };
    return c;
  };
  state.sb = {
    rpc: async (name, args) => {
      state.calls.push({ name, args });
      if (name === 'health_survey_detail') {
        if (detailError) return { data: null, error: { message: detailError } };
        return { data: { found: true, survey: state.survey, symptoms: [], attachments: [], has_pdf: false, reviewer: 'Owner', ...extra }, error: null };
      }
      if (name === 'consultant_notes_for') return { data: [], error: null };
      if (name === 'update_survey_particulars_v2' && v2Error) return { data: null, error: { message: v2Error } };
      if (name === 'review_health_survey') {
        state.survey = { ...state.survey, acidity_result: args.p_acidity, health_goals: args.p_health_goals,
                         remarks_condition: args.p_condition, remarks_recommendation: args.p_recommendation };
        return { data: null, error: null };
      }
      if (name === 'upsert_consultant_survey') {
        state.survey = { ...SURVEY(), id: 'hs-new', survey_no: 'HS-NEW', customer_id: 'c-2', store_id: args.p_store_id,
                         acidity_result: null, health_goals: null, remarks_condition: null, reviewed_at: null };
        return { data: 'hs-new', error: null };
      }
      return { data: null, error: null };
    },
    from: chain,
  };
  return state;
}

async function mount(role, props, db) {
  globalThis.__ROLE__ = role;
  globalThis.__SB__ = db.sb;
  const node = document.createElement('div');
  document.body.appendChild(node);
  const root = createRoot(node);
  const saved = [];
  await act(async () => {
    root.render(React.createElement(SurveyDetailModal, { onClose() {}, onSaved() { saved.push(1); }, ...props }));
  });
  await act(async () => { await new Promise(r => setTimeout(r, 10)); });
  const $ = sel => node.querySelector(sel);
  const flush = async () => { await act(async () => { await new Promise(r => setTimeout(r, 10)); }); };
  return {
    node, $, saved, text: () => node.textContent,
    async click(sel) { await act(async () => { Simulate.click(typeof sel === 'string' ? $(sel) : sel); }); await flush(); },
    async change(sel, value) {
      await act(async () => { Simulate.change(typeof sel === 'string' ? $(sel) : sel, { target: { value } }); });
    },
    calls: name => db.calls.filter(c => c.name === name),
    close() { act(() => root.unmount()); node.remove(); },
  };
}

test('CUSTOMERS-4: Not answered stays Not answered, and only the answer changed is sent', async () => {
  const db = makeDb();
  const ui = await mount('staff', { surveyId: 'hs-1' }, db);
  try {
    assert.match(ui.text(), /Medical\/physical condition: Not answered/);
    assert.match(ui.text(), /Sex.*Other/);
    await ui.click('[data-edit-details]');
    assert.equal(ui.$('[data-declaration="has_medical_condition"]').value, '');
    assert.equal(ui.$('[data-declaration="drinks_alcohol"]').value, 'no');
    await ui.change('[data-declaration="smokes"]', 'yes');
    await ui.click('[data-save-details]');
    const sent = ui.calls('update_survey_particulars_v2');
    assert.equal(sent.length, 1);
    assert.deepEqual(sent[0].args, { p_survey_id: 'hs-1', p_changes: { smokes: true }, p_reason: null });
    assert.equal(ui.calls('update_survey_particulars').length, 0, 'the old function is not called');
  } finally { ui.close(); }
});

test('CUSTOMERS-4: saving with nothing changed sends nothing', async () => {
  const db = makeDb();
  const ui = await mount('staff', { surveyId: 'hs-1' }, db);
  try {
    await ui.click('[data-edit-details]');
    await ui.click('[data-save-details]');
    assert.equal(ui.calls('update_survey_particulars_v2').length, 0);
  } finally { ui.close(); }
});

test('Q9: staff are told a filled-in date of birth is not theirs to change; nothing is sent', async () => {
  const db = makeDb();
  const ui = await mount('staff', { surveyId: 'hs-1' }, db);
  try {
    await ui.click('[data-edit-details]');
    await ui.change('[aria-label="Day of birth"]', '7');
    await ui.click('[data-save-details]');
    assert.match(ui.text(), /Only an Owner or Manager can change a date of birth that is already filled in\./);
    assert.equal(ui.calls('update_survey_particulars_v2').length, 0);
  } finally { ui.close(); }
});

test('Q9: an Owner gives a reason, which is sent with the new date', async () => {
  const db = makeDb();
  const ui = await mount('owner', { surveyId: 'hs-1' }, db);
  try {
    await ui.click('[data-edit-details]');
    await ui.change('[aria-label="Day of birth"]', '7');
    assert.ok(ui.$('[data-edit-reason]'), 'a reason is asked for');
    await ui.click('[data-save-details]');
    assert.match(ui.text(), /Give a reason for this change/);
    assert.equal(ui.calls('update_survey_particulars_v2').length, 0);
    await ui.change('[data-edit-reason]', 'Checked her IC');
    await ui.click('[data-save-details]');
    assert.deepEqual(ui.calls('update_survey_particulars_v2')[0].args,
      { p_survey_id: 'hs-1', p_changes: { date_of_birth: '1981-05-07' }, p_reason: 'Checked her IC' });
  } finally { ui.close(); }
});

test('CUSTOMERS-K1: Save Review is off until something changes, and the saved text stays in the boxes', async () => {
  const db = makeDb();
  const ui = await mount('owner', { surveyId: 'hs-1' }, db);
  try {
    assert.equal(ui.$('[data-review="cond"]').value, 'Tight back');
    assert.equal(ui.$('[data-save-review]').disabled, true, 'nothing changed yet');
    await ui.change('[data-review="cond"]', 'Better');
    assert.equal(ui.$('[data-save-review]').disabled, false);
    await ui.click('[data-save-review]');
    assert.equal(ui.calls('review_health_survey').length, 1);
    assert.equal(ui.$('[data-review="cond"]').value, 'Better', 'the boxes show what was saved, not emptied');
    assert.equal(ui.$('[data-review="goals"]').value, 'Sleep');
    assert.equal(ui.$('[data-save-review]').disabled, true, 'a second press has nothing to save');
  } finally { ui.close(); }
});

test('CUSTOMERS-K1: after Save Review, Submit as Note waits for a change, so the review is not noted twice', async () => {
  const db = makeDb();
  const ui = await mount('owner', { surveyId: 'hs-1' }, db);
  try {
    assert.equal(ui.$('[data-submit-note]').disabled, true, 'the boxes hold the saved review');
    await ui.change('[data-review="cond"]', 'Better');
    assert.equal(ui.$('[data-submit-note]').disabled, false);
    await ui.click('[data-save-review]');
    assert.equal(ui.calls('add_consultant_note').length, 1, 'Save Review notes it once');
    assert.equal(ui.$('[data-review="cond"]').value, 'Better');
    assert.equal(ui.$('[data-submit-note]').disabled, true, 'the saved review is already a note');
    assert.match(ui.$('[data-submit-note]').title, /saved review/);
    await ui.click('[data-submit-note]');
    assert.equal(ui.calls('add_consultant_note').length, 1, 'no second, identical note');
    await ui.change('[data-review="rec"]', 'Walk daily');
    assert.equal(ui.$('[data-submit-note]').disabled, false, 'a change can be noted');
    await ui.click('[data-submit-note]');
    assert.equal(ui.calls('add_consultant_note').length, 2);
    assert.equal(ui.calls('add_consultant_note')[1].args.p_recommendation, 'Walk daily');
  } finally { ui.close(); }
});

test('CUSTOMERS-K1: emptied boxes do not replace a saved review', async () => {
  const db = makeDb();
  const ui = await mount('owner', { surveyId: 'hs-1' }, db);
  try {
    await ui.change('[data-review="goals"]', '');
    await ui.change('[data-review="cond"]', '');
    assert.equal(ui.$('[data-save-review]').disabled, true);
    assert.ok(ui.$('[data-review-blanks]'), 'the window says why');
    await ui.click('[data-save-review]');
    assert.equal(ui.calls('review_health_survey').length, 0);
  } finally { ui.close(); }
});

test('CUSTOMERS-5: Start survey makes nothing until the first save; M1: the store is chosen first', async () => {
  const db = makeDb({ customer: { id: 'c-2', first_name: 'Cleo', last_name: 'Testthree', full_name: 'Cleo Testthree',
                                  phone: '+61491570737', email: 'cleo@example.com', date_of_birth: null, gender: 'female', occupation: null } });
  const stores = [{ store_id: 'st-a', store_name: 'Store A' }, { store_id: 'st-b', store_name: 'Store B' }];
  const ui = await mount('staff', { surveyId: null, customer: { customer_id: 'c-2', full_name: 'Cleo Testthree' }, stores }, db);
  try {
    assert.equal(ui.calls('upsert_consultant_survey').length, 0, 'opening makes no record');
    assert.ok(ui.$('[data-start-note]'));
    assert.ok(ui.$('#survey-store'), 'a person with two stores chooses one');
    await ui.click('[data-edit-details]');
    await ui.change('[data-declaration="smokes"]', 'no');
    await ui.click('[data-save-details]');
    assert.match(ui.text(), /Choose the store for this survey first\./);
    assert.equal(ui.calls('upsert_consultant_survey').length, 0);
    await ui.change('#survey-store', 'st-b');
    await ui.click('[data-save-details]');
    assert.deepEqual(ui.calls('upsert_consultant_survey')[0].args, { p_customer_id: 'c-2', p_store_id: 'st-b' });
    assert.deepEqual(ui.calls('update_survey_particulars_v2')[0].args,
      { p_survey_id: 'hs-new', p_changes: { smokes: false }, p_reason: null });
    assert.ok(ui.saved.length >= 1, 'the list is told a survey was made');
  } finally { ui.close(); }
});

test('CUSTOMERS-5: a file added first makes the survey at the one store the person has', async () => {
  const db = makeDb({ customer: { id: 'c-2', full_name: 'Cleo Testthree' } });
  const ui = await mount('owner', { surveyId: null, customer: { customer_id: 'c-2', full_name: 'Cleo Testthree' },
                                    stores: [{ store_id: 'st-a', store_name: 'Store A' }] }, db);
  try {
    assert.equal(ui.$('#survey-store'), null, 'one store: no question');
    await ui.click('[data-add-file]');
    assert.deepEqual(ui.calls('upsert_consultant_survey')[0].args, { p_customer_id: 'c-2', p_store_id: 'st-a' });
    assert.deepEqual(globalThis.__FILE_TARGET__, { surveyId: 'hs-new', storeId: 'st-a' });
  } finally { ui.close(); }
});

test('CUSTOMERS-5: when the first save fails after the survey was made, the window shows the survey and the error', async () => {
  const db = makeDb({ customer: { id: 'c-2', first_name: 'Cleo', last_name: 'Testthree', full_name: 'Cleo Testthree' },
                      v2Error: 'A reason is required to change a customer\'s phone number' });
  const ui = await mount('staff', { surveyId: null, customer: { customer_id: 'c-2', full_name: 'Cleo Testthree' },
                                    stores: [{ store_id: 'st-a', store_name: 'Store A' }] }, db);
  try {
    await ui.click('[data-edit-details]');
    await ui.change('[data-declaration="smokes"]', 'yes');
    await ui.click('[data-save-details]');
    assert.equal(ui.calls('upsert_consultant_survey').length, 1);
    assert.match(ui.text(), /HS-NEW/, 'the new survey is shown');
    assert.match(ui.text(), /A reason is required to change a customer's phone number/);
  } finally { ui.close(); }
});

test('CUSTOMERS-14: a survey that cannot be opened says why', async () => {
  const db = makeDb({ detailError: 'Your role cannot do this.' });
  const ui = await mount('staff', { surveyId: 'hs-1' }, db);
  try {
    assert.match(ui.text(), /The survey could not be opened: Your role cannot do this\./);
    assert.doesNotMatch(ui.text(), /not found/i);
  } finally { ui.close(); }
});

test('CUSTOMERS-14: another store\'s signed PDF is explained, not offered', async () => {
  const db = makeDb({ extra: { has_pdf: false, pdf_other_store: true } });
  const ui = await mount('staff', { surveyId: 'hs-1' }, db);
  try {
    assert.ok(ui.$('[data-pdf-other-store]'));
    assert.doesNotMatch(ui.text(), /Signed PDF/);
  } finally { ui.close(); }
});

test.after(async () => { dom.window.close(); await rm(dir, { recursive: true, force: true }); });
