// The Affiliates page's list of new affiliates who may already be customers
// (437; the Owner, 20 Oct 2026, decision 6), rendered for real against a fake
// backend.
//
//   L1 An Owner or Manager sees each affiliate on a fresh record with why it
//      is listed, and each customer it may be with how they match; a customer
//      who cannot be linked has the button off and says why.
//   L2 Link to this customer asks first, says what moves, and sends one link
//      with a request id made when the window opened (a second press is the
//      same link); the list reloads.
//   L3 An answer the server refused (someone linked it first) stays in the
//      window with the server's words.
//   L4 Keep separate needs a reason and sends it.
//   L5 Before 437 is on the server there is no list and no error; Staff never
//      see the list.
//   L6 The window says who is who (the names alone can be the same: phone and
//      email of both), warns when the customer is protected, says a customer
//      with an affiliate record of their own keeps it and its code, and reads
//      "Linking…" (Cancel off) while the link is sent.
//   L7 (AFF-SIGNUP-12) The window shows both phones; when they differ, a tick
//      box "Use the phone they signed up with", unticked to start when the
//      server does not suggest it: unticked it sends p_use_signup_phone false
//      and says plainly that a later website or referral-page registration
//      on the sign-up phone becomes a new customer and can earn another
//      affiliate commission; ticked it sends true and says the phone changes
//      as on the Customers page. The same phone: no tick box. What was
//      changed is said after.
//   L8 (AFF-SIGNUP-12) The window says what happens to the email: copied
//      onto a customer with none, kept, or left because another customer has
//      it; the server's notes are shown after the link.
//   L9 (AFF-SIGNUP-12) A phone the server refuses (3 customers have it)
//      keeps the window open with its words; unticked, the retry is the same
//      request.
//   L10 (AFF-SIGNUP-13) Twin records: the entry and the customer are
//      flagged, with what waits under To match and the fix (an Owner
//      unlinks the wrong login, then links), naming the row to unlink by its
//      referral code and the one not to (the new sign-up's code).
//   L11 (AFF-SIGNUP-14) Linking to a customer with a code of their own warns
//      that links shared with the new code stop crediting anyone, naming
//      both codes; not when the code moves with the login.
//   L12 (AFF-SIGNUP-16) The tick box starts as the server suggests: ticked
//      when the email cannot be copied (the customer keeps their own, or
//      another customer has it) or when seminar registrations or QR forms of
//      the sign-up wait under To match, saying why with the counts (the row
//      says what waits too); staff can untick it, and then false is sent.
//      Not offered for the same phone whatever the suggestion.
//   L13 (AFF-SIGNUP-17) After the link, the commission earned on the paid
//      invoices moved is listed (invoice, tier, referrer, amount, blocked
//      rows, the date), and so are invoices with none due or refused; the
//      window says beforehand that it happens. A press after a lost answer
//      is the same request; the server's replayed answer (what the link did
//      then) is shown the same way, saying it had already gone through.
//   L14 (AFF-SIGNUP-18) A login joined on the phone alone under another name
//      is shown as "May be someone else" with the name typed and the
//      record's; no Link and no Keep separate; Same person needs a note and
//      sends it; an Owner gets Unlink login for the record (the unlink
//      window opens for it), a Manager the fix in words only. The unlink
//      window says how that login was joined (the phone alone, the name
//      typed) and what happens now (a record of their own at the next
//      sign-in, no claim to reject), never "the verified email, phone and
//      name matched"; from the directory it says so without the name.
//
// src/pages/AffiliatesPage.tsx is bundled with esbuild and mounted in jsdom;
// only the Supabase client, the auth context and the QR library are stubbed.
// Every name, phone and email below is invented (ACMA fictional numbers).
//
// Run: node --test scripts/affiliate-claims/tests/affiliates-page-437.test.mjs
import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import { build } from 'esbuild';
import { JSDOM } from 'jsdom';

const REPO = fileURLToPath(new URL('../../../', import.meta.url));
const dom = new JSDOM('<!doctype html><html><body><div id="root"></div></body></html>', { url: 'https://affiliates.invalid', pretendToBeVisual: true });
for (const k of ['window', 'document', 'navigator', 'HTMLElement', 'HTMLInputElement', 'HTMLSelectElement', 'HTMLTextAreaElement', 'Element',
  'Node', 'Event', 'KeyboardEvent', 'MouseEvent', 'getComputedStyle', 'requestAnimationFrame', 'cancelAnimationFrame', 'MutationObserver']) {
  Object.defineProperty(globalThis, k, { value: dom.window[k], configurable: true, writable: true });
}
dom.window.confirm = () => true;
globalThis.IS_REACT_ACT_ENVIRONMENT = true;
globalThis.MessageChannel = class {
  constructor() {
    const port = () => ({ onmessage: null, close() {} });
    this.port1 = port(); this.port2 = port();
    this.port1.postMessage = data => setImmediate(() => this.port2.onmessage?.({ data }));
    this.port2.postMessage = data => setImmediate(() => this.port1.onmessage?.({ data }));
  }
};
const consoleError = console.error;
console.error = (...a) => { if (!String(a[0]).includes('not wrapped in act')) consoleError(...a); };

const built = await build({
  stdin: {
    contents: `
      import React from 'react';
      export { default as AffiliatesPage } from './src/pages/AffiliatesPage';
      export { createRoot } from 'react-dom/client';
      export { act } from 'react';
      export { React };`,
    loader: 'tsx', resolveDir: REPO,
  },
  bundle: true, write: false, format: 'esm', jsx: 'automatic', platform: 'browser',
  loader: { '.css': 'empty' }, logLevel: 'silent',
  define: { 'process.env.NODE_ENV': '"development"', 'import.meta.env': '{}' },
  plugins: [{ name: 'stubs', setup(b) {
    b.onResolve({ filter: /(^|\/)lib\/supabase$/ }, () => ({ path: 'supabase', namespace: 'stub' }));
    b.onResolve({ filter: /(^|\/)context\/AuthContext$/ }, () => ({ path: 'auth', namespace: 'stub' }));
    b.onResolve({ filter: /^qrcode$/ }, () => ({ path: 'qrcode', namespace: 'stub' }));
    b.onLoad({ filter: /^supabase$/, namespace: 'stub' }, () => ({ loader: 'js',
      contents: 'export const supabase = { from: (...a) => globalThis.__backend.client.from(...a), rpc: (...a) => globalThis.__backend.client.rpc(...a) };' }));
    b.onLoad({ filter: /^auth$/, namespace: 'stub' }, () => ({ loader: 'js',
      contents: 'export const useAuth = () => globalThis.__auth; export const AuthProvider = ({ children }) => children;' }));
    b.onLoad({ filter: /^qrcode$/, namespace: 'stub' }, () => ({ loader: 'js', contents: 'export default { toCanvas: async () => {} };' }));
  } }],
});
const { AffiliatesPage, createRoot, act, React } =
  await import('data:text/javascript;base64,' + Buffer.from(built.outputFiles[0].text).toString('base64'));

const MISSING = { code: 'PGRST202', message: 'Could not find the function public.affiliate_signup_matches_open without parameters in the schema cache' };
const makeMatches = () => [{
  match_id: 'm-dan', signed_up_at: '2026-10-21T03:00:00Z', reason: 'shared_phone',
  entered_name: 'Dan Testshare', entered_phone: '+61491572983',
  customer_id: 'c-dan', customer_name: 'Dan Testshare', phone: '+61491572983', email: 'dan-437@example.com',
  login_email: 'dan-437@example.com', referral_code: 'T437DAN', referrals: 1,
  candidates: [
    { customer_id: 'c-bea', name: 'Bea Testshare', phone: '+61491572983', email: null, created_at: '2025-01-01T00:00:00Z',
      matched_by: ['phone'], has_login: true, protected: false, problem: 'This customer already has an affiliate login.' },
    { customer_id: 'c-cal', name: 'Cal Testshare', phone: '+61491572983', email: 'cal-437@example.com', created_at: '2025-02-01T00:00:00Z',
      matched_by: ['phone', 'name'], has_login: false, protected: true, problem: null },
  ],
}];
function createBackend() {
  const b = { calls: [], handlers: {}, failures: new Map(), matches: makeMatches() };
  const rpcs = {
    affiliate_admin_directory: () => [],
    affiliate_staff_directory: () => ({ total: 0, rows: [] }),
    affiliate_pending_claims: () => [],
    affiliate_rejected_claims: () => [],
    referral_signup_checks_pending: () => [],
    affiliate_signup_matches_open: () => b.matches,
    link_affiliate_signup: () => { b.matches = []; return { ok: true, customer_id: 'c-cal', retired: 'c-dan', moved: {} }; },
    keep_affiliate_signup_separate: () => { b.matches = []; return { ok: true }; },
    confirm_affiliate_signup_same_person: () => { b.matches = []; return { ok: true }; },
    affiliate_portal_login: () => ({ linked: true, login_email: 'rina-437@example.com', status: 'claimed', linked_at: '2026-10-21T03:00:00Z', claims: [] }),
  };
  class Query {
    constructor(kind, name, args) { Object.assign(this, { kind, name, args, single: false }); }
    select() { return this; } eq() { return this; } is() { return this; } in() { return this; } or() { return this; }
    order() { return this; } limit() { return this; } maybeSingle() { this.single = true; return this; }
    async exec() {
      b.calls.push({ kind: this.kind, name: this.name, args: this.args });
      await Promise.resolve();
      if (b.failures.has(this.name)) {
        const f = b.failures.get(this.name);
        return { data: null, error: typeof f === 'string' ? { message: f } : f };
      }
      if (this.kind === 'rpc') {
        const fn = b.handlers[this.name] ?? rpcs[this.name];
        if (!fn) return { data: null, error: { message: `unknown rpc ${this.name}` } };
        return { data: structuredClone(fn(this.args)), error: null };
      }
      return { data: this.single ? null : [], error: null };
    }
    then(res, rej) { return this.exec().then(res, rej); }
  }
  b.client = { from: name => new Query('table', name, null), rpc: (name, args) => new Query('rpc', name, args) };
  return b;
}
const USERS = {
  owner: { id: 'u-own', full_name: 'Owner One', role: 'owner', is_active: true },
  manager: { id: 'u-mgr', full_name: 'Manager One', role: 'manager', is_active: true },
  staff: { id: 'u-staff', full_name: 'Staff One', role: 'staff', is_active: true },
};
let root = null;
let backend = null;
const tick = async (n = 10) => { for (let i = 0; i < n; i++) await act(async () => { await new Promise(r => setTimeout(r, 0)); }); };
async function mount(role, setup) {
  if (root) await act(async () => root.unmount());
  document.body.innerHTML = '<div id="root"></div>';
  backend = createBackend();
  globalThis.__backend = backend;
  globalThis.__auth = { profile: USERS[role] };
  setup?.(backend);
  root = createRoot(document.getElementById('root'));
  await act(async () => root.render(React.createElement(AffiliatesPage)));
  await tick();
}
const click = async el => {
  assert.ok(el, 'the element to click exists');
  await act(async () => { el.dispatchEvent(new dom.window.MouseEvent('click', { bubbles: true })); });
  await tick();
};
const button = (label, scope = document) => [...scope.querySelectorAll('button')].find(b => b.textContent.trim() === label);
async function setValue(el, value) {
  assert.ok(el, 'the field exists');
  const proto = el.tagName === 'TEXTAREA' ? dom.window.HTMLTextAreaElement.prototype : dom.window.HTMLInputElement.prototype;
  await act(async () => {
    Object.getOwnPropertyDescriptor(proto, 'value').set.call(el, value);
    el.dispatchEvent(new dom.window.Event('input', { bubbles: true }));
  });
  await tick(2);
}
const modal = () => document.querySelector('.modal');
const callsOf = name => backend.calls.filter(c => c.name === name);
const section = () => document.querySelector('[data-section="signup-matches"]');
const candidate = id => document.querySelector(`[data-candidate="${id}"]`);
after(async () => { if (root) await act(async () => root.unmount()); dom.window.close(); });

test('L1: a Manager sees each new affiliate on a fresh record, why it is listed, and whom it may be', async () => {
  await mount('manager');
  assert.ok(section(), 'the list shows');
  const t = section().textContent;
  assert.match(t, /New affiliates who may already be customers \(1\)/);
  assert.match(t, /Dan Testshare/);
  assert.match(t, /dan-437@example\.com/);
  assert.match(t, /T437DAN · 1 referral/);
  assert.match(t, /Several customers have this phone/);
  assert.match(candidate('c-cal').textContent, /Cal Testshare.*Phone.*Name.*Protected/);
  const bea = candidate('c-bea').querySelector('[data-action="link"]');
  assert.equal(bea.disabled, true, 'a customer with a portal login cannot be linked');
  assert.equal(bea.getAttribute('title'), 'This customer already has an affiliate login.');
  assert.match(candidate('c-bea').textContent, /already has an affiliate login/);
  assert.equal(candidate('c-cal').querySelector('[data-action="link"]').disabled, false);
});

test('L2: Link to this customer asks first, sends one link with the window\'s request id, and reloads', async () => {
  await mount('owner');
  await click(candidate('c-cal').querySelector('[data-action="link"]'));
  assert.ok(modal(), 'a window asks first');
  assert.match(modal().textContent, /Link the new record to Cal Testshare/);
  assert.match(modal().textContent, /referral code T437DAN and 1 referral move to Cal Testshare/);
  assert.equal(callsOf('link_affiliate_signup').length, 0, 'nothing is sent before confirming');
  await setValue(modal().querySelector('textarea'), '  Checked by phone  ');
  await click(modal().querySelector('[data-action="confirm-link"]'));
  const sent = callsOf('link_affiliate_signup');
  assert.equal(sent.length, 1);
  assert.equal(sent[0].args.p_match_id, 'm-dan');
  assert.equal(sent[0].args.p_customer_id, 'c-cal');
  assert.equal(sent[0].args.p_note, 'Checked by phone');
  assert.match(sent[0].args.p_request_id, /^[0-9a-f-]{36}$/);
  assert.equal(sent[0].args.p_use_signup_phone, false, 'the same phone: nothing to use');
  assert.equal(modal(), null, 'the window closes');
  assert.match(document.body.textContent, /Dan Testshare is linked to Cal Testshare/);
  assert.equal(section(), null, 'the list reloads (now empty)');
});

test('L3: a link the server refuses stays in the window with its words, and a retry is the same request', async () => {
  await mount('manager', b => {
    b.handlers.link_affiliate_signup = () => ({ ok: false, message: 'This sign-up was linked to a customer already. Reload the page.' });
  });
  await click(candidate('c-cal').querySelector('[data-action="link"]'));
  await click(modal().querySelector('[data-action="confirm-link"]'));
  assert.match(modal().textContent, /linked to a customer already/);
  await click(modal().querySelector('[data-action="confirm-link"]'));
  const ids = callsOf('link_affiliate_signup').map(c => c.args.p_request_id);
  assert.equal(ids.length, 2);
  assert.equal(ids[0], ids[1], 'the same window sends the same request id');
});

test('L4: Keep separate needs a reason, then sends it', async () => {
  await mount('owner');
  await click(button('Keep separate', section()));
  assert.ok(modal(), 'a reason window opens');
  await click(button('Keep separate', modal()));
  assert.equal(callsOf('keep_affiliate_signup_separate').length, 0, 'not without a reason');
  await setValue(modal().querySelector('textarea'), 'Her brother, sharing the phone');
  await click(button('Keep separate', modal()));
  assert.deepEqual(callsOf('keep_affiliate_signup_separate').map(c => c.args), [{ p_match_id: 'm-dan', p_note: 'Her brother, sharing the phone' }]);
  assert.match(document.body.textContent, /Dan Testshare is kept as a separate customer/);
});

test('L5: before 437 there is no list and no error; Staff never see the list', async () => {
  await mount('owner', b => b.failures.set('affiliate_signup_matches_open', MISSING));
  assert.equal(section(), null);
  assert.equal(document.querySelector('[data-error="signup-matches"]'), null);
  await mount('manager', b => b.failures.set('affiliate_signup_matches_open', 'connection reset'));
  assert.match(document.querySelector('[data-error="signup-matches"]')?.textContent ?? '', /connection reset/);
  await mount('staff');
  assert.equal(section(), null);
  assert.equal(callsOf('affiliate_signup_matches_open').length, 0, 'staff do not ask for it');
});

test('L6: the window says who is who, warns about a protected customer, and keeps the customer\'s own code', async () => {
  let release;
  await mount('owner', b => {
    b.matches[0].candidates[1].name = 'Dan Testshare';                 // the same name as the new record
    b.matches[0].candidates[1].own_referral_code = 'T437CAL';
    b.handlers.link_affiliate_signup = () => { b.matches = []; return { ok: true, customer_id: 'c-cal', retired: 'c-dan', moved: {}, kept_own_affiliate: true }; };
  });
  await click(candidate('c-cal').querySelector('[data-action="link"]'));
  const m = modal();
  assert.match(m.querySelector('[data-detail="new-record"]').textContent, /New record: Dan Testshare · \+61491572983 · dan-437@example\.com/);
  assert.match(m.querySelector('[data-detail="existing-customer"]').textContent, /Existing customer: Dan Testshare · \+61491572983 · cal-437@example\.com/);
  assert.match(m.querySelector('[data-flag="protected"]').textContent, /This customer is protected: .*Link only if you have checked it is the same person\./);
  assert.match(m.textContent, /keeps their own affiliate record and referral code T437CAL, and the affiliate login moves onto it; the new record's code T437DAN is retired\./);
  assert.match(candidate('c-cal').querySelector('[data-note="own-code"]').textContent, /Has their own affiliate code T437CAL, kept if linked\./);
  assert.doesNotMatch(m.textContent, /1 referral move to/);
  // While the link is on its way: "Linking…", and neither button can be pressed.
  const gate = new Promise(r => { release = r; });
  const realRpc = backend.client.rpc;
  backend.client.rpc = (name, args) => {
    if (name !== 'link_affiliate_signup') return realRpc(name, args);
    const q = realRpc(name, args);
    return { then: (res, rej) => gate.then(() => q.then(res, rej)) };
  };
  await act(async () => { m.querySelector('[data-action="confirm-link"]').dispatchEvent(new dom.window.MouseEvent('click', { bubbles: true })); });
  assert.equal(m.querySelector('[data-action="confirm-link"]').textContent, 'Linking…');
  assert.equal(m.querySelector('[data-action="confirm-link"]').disabled, true);
  assert.equal(button('Cancel', m).disabled, true);
  release();
  await tick();
  assert.equal(modal(), null);
  assert.match(document.body.textContent, /now uses Dan Testshare's own affiliate record and referral code T437CAL/);
});

test('L7: both phones, and "Use the phone they signed up with", unticked to start', async () => {
  await mount('owner', b => {
    b.matches[0].candidates[1].phone = '+61491570737';               // Cal's own, older number
    b.handlers.link_affiliate_signup = args => {
      b.matches = [];
      return { ok: true, customer_id: 'c-cal', retired: 'c-dan', moved: {}, phone_changed: !!args.p_use_signup_phone,
               phone: args.p_use_signup_phone ? '+61491572983' : '+61491570737', email_copied: null, notes: [] };
    };
  });
  await click(candidate('c-cal').querySelector('[data-action="link"]'));
  let m = modal();
  assert.match(m.querySelector('[data-detail="customer-phone"]').textContent, /Cal Testshare's phone: \+61491570737/);
  assert.match(m.querySelector('[data-detail="signup-phone"]').textContent, /The phone they signed up with: \+61491572983/);
  const box = m.querySelector('[data-field="use-signup-phone"] input[type="checkbox"]');
  assert.ok(box, 'a tick box is offered');
  assert.match(m.querySelector('[data-field="use-signup-phone"]').textContent, /Use the phone they signed up with/);
  assert.equal(box.checked, false, 'unticked to start');
  assert.equal(m.querySelector('[data-note="phone-outcome"]').textContent,
    'Cal Testshare keeps +61491570737. A later website or referral-page registration on +61491572983 will not find Cal Testshare: '
    + 'it becomes a new customer and, through another affiliate\'s link, can earn that affiliate commission (for a seminar VIP at once).');
  assert.equal(m.querySelector('[data-note="phone-default"]'), null, 'no suggestion: nothing to explain');
  await click(m.querySelector('[data-action="confirm-link"]'));
  assert.equal(callsOf('link_affiliate_signup')[0].args.p_use_signup_phone, false);
  assert.doesNotMatch(document.body.textContent, /phone is now/);

  await mount('owner', b => {
    b.matches[0].candidates[1].phone = '+61491570737';
    b.handlers.link_affiliate_signup = () => {
      b.matches = [];
      return { ok: true, customer_id: 'c-cal', retired: 'c-dan', moved: {}, phone_changed: true, phone: '+61491572983',
               email_copied: null, notes: [] };
    };
  });
  await click(candidate('c-cal').querySelector('[data-action="link"]'));
  m = modal();
  await click(m.querySelector('[data-field="use-signup-phone"] input'));
  assert.equal(m.querySelector('[data-field="use-signup-phone"] input').checked, true);
  assert.match(m.querySelector('[data-note="phone-outcome"]').textContent,
    /Cal Testshare's phone becomes \+61491572983, as a phone change on the Customers page: the old number goes into the phone history, and at most 3 customers may share a phone\./);
  await click(m.querySelector('[data-action="confirm-link"]'));
  assert.equal(callsOf('link_affiliate_signup')[0].args.p_use_signup_phone, true);
  assert.equal(modal(), null);
  assert.match(document.body.textContent, /Dan Testshare is linked to Cal Testshare\..*Cal Testshare's phone is now \+61491572983\./);

  // The same phone (the fixture as it is): nothing to tick.
  await mount('owner');
  await click(candidate('c-cal').querySelector('[data-action="link"]'));
  assert.equal(modal().querySelector('[data-field="use-signup-phone"]'), null);
  assert.match(modal().querySelector('[data-note="phone-outcome"]').textContent, /The same phone\./);
});

test('L8: the window says what happens to the email, and the server\'s notes follow the link', async () => {
  await mount('manager');
  await click(candidate('c-cal').querySelector('[data-action="link"]'));
  assert.match(modal().querySelector('[data-detail="email"]').textContent, /Cal Testshare keeps their own email, cal-437@example\.com\./);

  await mount('manager', b => {
    Object.assign(b.matches[0].candidates[1], { email: null, email_on_link: 'copy' });
    b.handlers.link_affiliate_signup = () => {
      b.matches = [];
      return { ok: true, customer_id: 'c-cal', retired: 'c-dan', moved: {}, phone_changed: false, phone: '+61491572983',
               email_copied: 'dan-437@example.com', notes: [] };
    };
  });
  await click(candidate('c-cal').querySelector('[data-action="link"]'));
  assert.match(modal().querySelector('[data-detail="email"]').textContent,
    /Cal Testshare has no email: the one they signed up with, dan-437@example\.com, will be copied onto them\./);
  await click(modal().querySelector('[data-action="confirm-link"]'));
  assert.match(document.body.textContent, /The email they signed up with, dan-437@example\.com, is now on Cal Testshare\./);

  const note = 'The email they signed up with, dan-437@example.com, was not copied onto Cal Testshare: another customer already has it.';
  await mount('manager', b => {
    Object.assign(b.matches[0].candidates[1], { email: null, email_on_link: 'in_use' });
    b.handlers.link_affiliate_signup = () => {
      b.matches = [];
      return { ok: true, customer_id: 'c-cal', retired: 'c-dan', moved: {}, phone_changed: false, phone: '+61491572983',
               email_copied: null, email_not_copied: 'in_use', notes: [note] };
    };
  });
  await click(candidate('c-cal').querySelector('[data-action="link"]'));
  assert.match(modal().querySelector('[data-detail="email"]').textContent,
    /Cal Testshare has no email, but another customer already has the one they signed up with \(dan-437@example\.com\), so it will not be copied\./);
  await click(modal().querySelector('[data-action="confirm-link"]'));
  assert.ok(document.body.textContent.includes(note), 'the server\'s note is shown');
});

test('L9: a phone the server refuses keeps the window open; unticked, the retry is the same request', async () => {
  const refused = 'The phone they signed up with, +61491572983, already belongs to 3 customers, so it cannot become Cal Testshare\'s phone. Nothing was linked or changed. Untick "use the phone they signed up with" and link again.';
  await mount('owner', b => {
    b.matches[0].candidates[1].phone = '+61491570737';
    b.handlers.link_affiliate_signup = args => args.p_use_signup_phone
      ? { ok: false, phone_refused: true, message: refused }
      : (b.matches = [], { ok: true, customer_id: 'c-cal', retired: 'c-dan', moved: {}, phone_changed: false, phone: '+61491570737', notes: [] });
  });
  await click(candidate('c-cal').querySelector('[data-action="link"]'));
  await click(modal().querySelector('[data-field="use-signup-phone"] input'));
  await click(modal().querySelector('[data-action="confirm-link"]'));
  assert.ok(modal(), 'the window stays');
  assert.equal(modal().querySelector('[data-error="link"]').textContent, refused);
  await click(modal().querySelector('[data-field="use-signup-phone"] input'));
  assert.equal(modal().querySelector('[data-field="use-signup-phone"] input').checked, false);
  await click(modal().querySelector('[data-action="confirm-link"]'));
  const sent = callsOf('link_affiliate_signup');
  assert.deepEqual(sent.map(c => c.args.p_use_signup_phone), [true, false]);
  assert.equal(sent[0].args.p_request_id, sent[1].args.p_request_id, 'the same window sends the same request id');
  assert.equal(modal(), null);
});

test('L10: twin records are flagged, with what waits under To match and the fix', async () => {
  const twin = b => {
    Object.assign(b.matches[0], { twin: true, twin_customer_id: 'c-bea' });
    b.matches[0].candidates[0].name = 'Dan Testshare';                // the very same name and phone, with a login
    b.matches[0].candidates[0].twin = true;
  };
  await mount('manager', b => { twin(b); b.matches[0].candidates[0].own_referral_code = 'T437BEA'; });
  const row = document.querySelector('[data-match="m-dan"]');
  assert.match(row.querySelector('[data-flag="twin-entry"]').textContent, /Twin records/);
  const bea = candidate('c-bea');
  assert.match(bea.querySelector('[data-flag="twin"]').textContent, /Same name and phone/);
  const note = bea.querySelector('[data-note="twin"]').textContent.replace(/\s+/g, ' ');
  assert.match(note, /Dan Testshare has the same name and phone as Dan Testshare, whose record already has an affiliate login\./);
  assert.match(note, /Until this is sorted out, this person's website registrations, VIP payments and QR health forms will wait under To match\./);
  // The Affiliates list shows two rows named Dan Testshare, each with Unlink
  // login: the note names the right one by its code, and the new sign-up's.
  assert.match(note, /To fix it, an Owner first unlinks the wrong login from Dan Testshare: in the Affiliates list below, use Unlink login on the Dan Testshare row with referral code T437BEA, not the one with code T437DAN \(that one is this new sign-up\)\. Then link this sign-up to Dan Testshare here\./);
  assert.ok(note.includes('T437BEA') && note.includes('T437DAN'), 'both codes are named');
  assert.equal(bea.querySelector('[data-note="own-code"]'), null, 'no second code note: it has a problem');
  assert.equal(bea.querySelector('[data-action="link"]').disabled, true, 'not linkable while it has the login');
  assert.equal(candidate('c-cal').querySelector('[data-flag="twin"]'), null);
  assert.equal(candidate('c-cal').querySelector('[data-note="twin"]'), null);
  // No code known for the twin: the row is named as before.
  await mount('manager', twin);
  assert.match(candidate('c-bea').querySelector('[data-note="twin"]').textContent.replace(/\s+/g, ' '),
    /To fix it, an Owner first unlinks the wrong login from Dan Testshare \(Unlink login, on Dan Testshare's row in the Affiliates list below\), then links this sign-up to Dan Testshare here\./);
  // Without the flag (the fixture as it is): nothing.
  await mount('manager');
  assert.equal(document.querySelector('[data-flag="twin-entry"]'), null);
  assert.equal(document.querySelector('[data-note="twin"]'), null);
});

test('L11: linking to a customer with a code of their own warns, naming both codes', async () => {
  await mount('owner', b => {
    Object.assign(b.matches[0].candidates[1], { own_referral_code: 'T437CAL', retires_new_code: true });
  });
  await click(candidate('c-cal').querySelector('[data-action="link"]'));
  assert.equal(modal().querySelector('[data-warning="retired-code"]').textContent,
    'Links shared with code T437DAN will stop crediting anyone. Ask them to share code T437CAL instead.');
  // No code of their own: the new code moves with the login, nothing to warn.
  await mount('owner', b => { b.matches[0].candidates[1].retires_new_code = false; });
  await click(candidate('c-cal').querySelector('[data-action="link"]'));
  assert.equal(modal().querySelector('[data-warning="retired-code"]'), null);
  assert.match(modal().textContent, /referral code T437DAN and 1 referral move to Cal Testshare/);
});

test('L12: the phone box starts as the server suggests, says why, and staff can change it', async () => {
  // Cal keeps his own email (the server suggests ticking), and 2 seminar
  // registrations and 1 QR form of this sign-up wait under To match.
  await mount('owner', b => {
    Object.assign(b.matches[0], { waiting: { seminar: 2, qr: 1 } });
    Object.assign(b.matches[0].candidates[1], { phone: '+61491570737', email_on_link: 'keep_own', use_signup_phone_default: true,
      use_signup_phone_why: ['email_keep_own', 'waiting_seminar', 'waiting_qr'] });
  });
  assert.equal(document.querySelector('[data-match="m-dan"] [data-note="waiting"]').textContent,
    'Waiting under To match: 2 seminar registrations and 1 QR health form.');
  await click(candidate('c-cal').querySelector('[data-action="link"]'));
  let m = modal();
  const box = () => m.querySelector('[data-field="use-signup-phone"] input');
  assert.equal(box().checked, true, 'ticked to start, as the server suggests');
  assert.equal(m.querySelector('[data-note="phone-default"]').textContent,
    'Ticked to start: Cal Testshare keeps their own email, so the email they signed up with is not copied; '
    + '2 seminar registrations and 1 QR health form for this sign-up are waiting under To match.');
  assert.match(m.querySelector('[data-note="phone-outcome"]').textContent, /Cal Testshare's phone becomes \+61491572983/);
  // Staff untick it: the plain warning, and false is sent.
  await click(box());
  assert.equal(box().checked, false);
  assert.match(m.querySelector('[data-note="phone-outcome"]').textContent,
    /A later website or referral-page registration on \+61491572983 will not find Cal Testshare: it becomes a new customer and, through another affiliate's link, can earn that affiliate commission \(for a seminar VIP at once\)\./);
  await click(m.querySelector('[data-action="confirm-link"]'));
  assert.equal(callsOf('link_affiliate_signup')[0].args.p_use_signup_phone, false, 'staff can change the tick');

  // Another customer has the email they signed up with: ticked, and sent ticked.
  await mount('manager', b => {
    Object.assign(b.matches[0].candidates[1], { phone: '+61491570737', email: null, email_on_link: 'in_use',
      use_signup_phone_default: true, use_signup_phone_why: ['email_in_use'] });
  });
  await click(candidate('c-cal').querySelector('[data-action="link"]'));
  m = modal();
  assert.equal(box().checked, true);
  assert.equal(m.querySelector('[data-note="phone-default"]').textContent,
    'Ticked to start: another customer already has the email they signed up with, so it is not copied.');
  await click(m.querySelector('[data-action="confirm-link"]'));
  assert.equal(callsOf('link_affiliate_signup')[0].args.p_use_signup_phone, true);

  // One QR form waiting only.
  await mount('manager', b => {
    Object.assign(b.matches[0], { waiting: { seminar: null, qr: 1 } });
    Object.assign(b.matches[0].candidates[1], { phone: '+61491570737', email: null, email_on_link: 'copy',
      use_signup_phone_default: true, use_signup_phone_why: ['waiting_qr'] });
  });
  await click(candidate('c-cal').querySelector('[data-action="link"]'));
  assert.equal(modal().querySelector('[data-note="phone-default"]').textContent,
    'Ticked to start: 1 QR health form for this sign-up is waiting under To match.');

  // Nothing suggested: unticked, nothing to explain, nothing waiting shown.
  await mount('manager', b => {
    Object.assign(b.matches[0].candidates[1], { phone: '+61491570737', email: null, email_on_link: 'copy',
      use_signup_phone_default: false, use_signup_phone_why: [] });
  });
  await click(candidate('c-cal').querySelector('[data-action="link"]'));
  m = modal();
  assert.equal(box().checked, false);
  assert.equal(m.querySelector('[data-note="phone-default"]'), null);
  assert.equal(document.querySelector('[data-match="m-dan"] [data-note="waiting"]'), null);

  // The same phone: no box, whatever the suggestion; nothing is sent ticked.
  await mount('owner', b => {
    Object.assign(b.matches[0].candidates[1], { use_signup_phone_default: true, use_signup_phone_why: ['email_keep_own'] });
  });
  await click(candidate('c-cal').querySelector('[data-action="link"]'));
  assert.equal(modal().querySelector('[data-field="use-signup-phone"]'), null);
  await click(modal().querySelector('[data-action="confirm-link"]'));
  assert.equal(callsOf('link_affiliate_signup')[0].args.p_use_signup_phone, false);
});

test('L13: after the link, the commission earned on the paid invoices moved is listed', async () => {
  await mount('owner', b => {
    b.handlers.link_affiliate_signup = () => {
      b.matches = [];
      return { ok: true, customer_id: 'c-cal', retired: 'c-dan', moved: {}, phone_changed: false, phone: '+61491572983', notes: [],
        commission_dated: '2026-10-21',
        commission_earned: [
          { invoice_id: 'i1', invoice_no: 'INV-2026-0101', dated: '2026-10-21', amount: 10.8,
            rows: [{ tier: 'tier1', referrer_name: 'Una Testupline', amount: 10.8, status: 'earned' },
                   { tier: 'tier2', referrer_name: 'Ula Testtop', amount: 0.54, status: 'blocked', block_reason: 'Affiliate Not Activated' }] },
          { invoice_id: 'i2', invoice_no: 'INV-2026-0102', dated: '2026-10-21', amount: 9,
            rows: [{ tier: 'tier1', referrer_name: 'Una Testupline', amount: 9, status: 'earned' }] }],
        commission_not_earned: [
          { invoice_id: 'i3', invoice_no: 'INV-2026-0103', why: 'none_due' },
          { invoice_id: 'i4', invoice_no: 'INV-2026-0104', why: 'refused', message: 'Commission review required' }] };
    };
  });
  await click(candidate('c-cal').querySelector('[data-action="link"]'));
  assert.match(modal().querySelector('[data-note="commission-on-link"]').textContent,
    /If Cal Testshare has a referrer, paid invoices on the new record that earned no commission earn it for them now, as at payment, dated today\./);
  await click(modal().querySelector('[data-action="confirm-link"]'));
  const t = document.body.textContent;
  assert.ok(t.includes('Commission earned on the paid invoices moved to Cal Testshare, dated 21/10/2026: '
    + 'INV-2026-0101: Tier 1 Una Testupline S$10.80, Tier 2 Ula Testtop S$0.54 (blocked: Affiliate Not Activated); '
    + 'INV-2026-0102: Tier 1 Una Testupline S$9.00.'), t);
  assert.ok(t.includes('No commission is due on INV-2026-0103 by the commission rules'), t);
  assert.ok(t.includes('Commission could not be earned on INV-2026-0104 (Commission review required): the link is done'), t);

  // A lost answer: the link went through but the page got an error. The
  // second press sends the same request id; the server answers replayed,
  // with what the link did then, and the page shows it.
  const earnedAnswer = {
    ok: true, replayed: true, customer_id: 'c-cal', retired: 'c-dan', moved: {}, phone_changed: false, phone: '+61491572983',
    email_copied: null, notes: [], commission_dated: '2026-10-21',
    commission_earned: [{ invoice_id: 'i5', invoice_no: 'INV-2026-0105', dated: '2026-10-21', amount: 47.25,
      rows: [{ tier: 'tier1', referrer_name: 'Una Testupline', amount: 45, status: 'earned' },
             { tier: 'tier2', referrer_name: 'Ula Testtop', amount: 2.25, status: 'earned' }] }],
    commission_not_earned: [{ invoice_id: 'i6', invoice_no: 'INV-2026-0106', why: 'none_due' }] };
  await mount('owner', b => {
    b.failures.set('link_affiliate_signup', 'TypeError: Failed to fetch');
    b.handlers.link_affiliate_signup = () => { b.matches = []; return earnedAnswer; };
  });
  await click(candidate('c-cal').querySelector('[data-action="link"]'));
  await click(modal().querySelector('[data-action="confirm-link"]'));
  assert.ok(modal() && modal().textContent.includes('Failed to fetch'), 'the window stays after the error, with it');
  backend.failures.delete('link_affiliate_signup');
  await click(modal().querySelector('[data-action="confirm-link"]'));
  const sent = callsOf('link_affiliate_signup').map(c => c.args.p_request_id);
  assert.equal(sent.length, 2);
  assert.equal(sent[0], sent[1], 'the second press is the same request');
  const r = document.body.textContent;
  assert.ok(r.includes('This link had already gone through on an earlier press; nothing was linked, changed or earned again. What it did then:'), r);
  assert.ok(r.includes('Commission earned on the paid invoice moved to Cal Testshare, dated 21/10/2026: '
    + 'INV-2026-0105: Tier 1 Una Testupline S$45.00, Tier 2 Ula Testtop S$2.25.'), r);
  assert.ok(r.includes('No commission is due on INV-2026-0106 by the commission rules'), r);

  // No referrer, no invoices: nothing about commission.
  await mount('owner');
  await click(candidate('c-cal').querySelector('[data-action="link"]'));
  await click(modal().querySelector('[data-action="confirm-link"]'));
  assert.doesNotMatch(document.body.textContent, /Commission earned|No commission is due|could not be earned/);
});

const someoneElse = () => ({
  match_id: 'm-rina', signed_up_at: '2026-10-21T03:00:00Z', reason: 'phone_other_name', kind: 'may_be_someone_else',
  entered_name: 'Rina Testfamily', entered_phone: '+61491570131',
  customer_id: 'c-siew', customer_name: 'Siew Lan Testfamily', phone: '+61491570131', email: null,
  login_email: 'rina-437@example.com', referral_code: 'T437SIEW', referrals: 0, twin: false, twin_customer_id: null,
  waiting: null, candidates: [],
});

test('L14: a phone-only join under another name is "May be someone else", with Same person and the fix', async () => {
  await mount('manager', b => { b.matches = [someoneElse(), ...makeMatches()]; });
  const row = document.querySelector('[data-match="m-rina"]');
  assert.ok(row, 'the entry is listed');
  assert.match(row.querySelector('[data-flag="someone-else"]').textContent, /May be someone else/);
  assert.match(row.textContent, /^Rina Testfamily/, 'listed under the name they typed');
  assert.equal(row.querySelector('[data-detail="typed-name"]').textContent, 'Name they typed: Rina Testfamily');
  assert.equal(row.querySelector('[data-detail="record-name"]').textContent, 'The record\'s name: Siew Lan Testfamily');
  assert.match(row.querySelector('[data-note="someone-else"]').textContent.replace(/\s+/g, ' '),
    /Rina Testfamily signed up on \+61491570131 and was let into Siew Lan Testfamily's affiliate account on the phone alone: .*If it is someone else \(a family member on the same phone, say\), an Owner unlinks the login from Siew Lan Testfamily \(Unlink login\); they get a customer record of their own at their next sign-in\./);
  assert.equal(row.querySelector('[data-action="link"]'), null, 'no Link: there is no new record');
  assert.equal(button('Keep separate', row), undefined, 'no Keep separate');
  assert.equal(row.querySelector('[data-action="unlink-joined"]'), null, 'a Manager cannot unlink');
  // The ordinary entry is still shown as before.
  assert.ok(document.querySelector('[data-match="m-dan"] [data-action="link"]'));
  // Same person needs a note, then sends it.
  await click(row.querySelector('[data-action="same-person"]'));
  assert.match(modal().textContent, /Rina Testfamily is Siew Lan Testfamily/);
  await click(button('Same person', modal()));
  assert.equal(callsOf('confirm_affiliate_signup_same_person').length, 0, 'not without a note');
  await setValue(modal().querySelector('textarea'), 'Called her: Rina is her English name');
  await click(button('Same person', modal()));
  assert.deepEqual(callsOf('confirm_affiliate_signup_same_person').map(c => c.args),
    [{ p_match_id: 'm-rina', p_note: 'Called her: Rina is her English name' }]);
  assert.match(document.body.textContent, /Siew Lan Testfamily: checked as the same person/);

  // A refusal stays in the window with the server's words.
  await mount('manager', b => {
    b.matches = [someoneElse()];
    b.handlers.confirm_affiliate_signup_same_person = () => ({ ok: false, message: 'This sign-up was checked already. Reload the page.' });
  });
  await click(document.querySelector('[data-match="m-rina"] [data-action="same-person"]'));
  await setValue(modal().querySelector('textarea'), 'Checked');
  await click(button('Same person', modal()));
  assert.match(modal().textContent, /This sign-up was checked already/);

  // An Owner: Unlink login opens the unlink window for the record it joined.
  await mount('owner', b => { b.matches = [someoneElse()]; });
  await click(document.querySelector('[data-match="m-rina"] [data-action="unlink-joined"]'));
  assert.match(modal().textContent, /Unlink portal login — Siew Lan Testfamily/);
  assert.deepEqual(callsOf('affiliate_portal_login').map(c => c.args), [{ p_customer_id: 'c-siew' }]);
  assert.match(modal().textContent, /rina-437@example\.com/);
  // It says how this login was joined, and what happens now (437).
  const w = modal().textContent.replace(/\s+/g, ' ');
  assert.equal(modal().querySelector('[data-detail="unlink-how"]').textContent.replace(/\s+/g, ' '),
    'How: at sign-up, on the phone alone, under the name “Rina Testfamily”, which is not this record\'s name (listed “May be someone else”).');
  assert.ok(w.includes('at their next sign-in they are let in at once on a customer record and affiliate account of their own (no account claim is made)'), w);
  assert.ok(w.includes('There is no claim to reject.'), w);
  assert.ok(w.includes('referrals made with that code while this login was linked too'), w);
  for (const stale of ['verified email', 'parks a new account claim', 'Reject that claim', 'A new claim from this login']) {
    assert.ok(!w.includes(stale), `no "${stale}": ${w}`);
  }

  // From the directory (not a listed entry), the window says how without a name.
  await mount('owner', b => {
    b.matches = [];
    b.handlers.affiliate_admin_directory = () => [{ customer_id: 'c-siew', name: 'Siew Lan Testfamily', status: 'active', manually_suspended: false,
      referral_code: 'T437SIEW', portal_account: 'claimed', direct_referrals: 0, tier2: 0, lifetime: 0, unpaid: 0, blocked: 0, last_commission: null }];
  });
  await click(document.querySelector('[aria-label="Unlink login of Siew Lan Testfamily"]'));
  assert.equal(modal().querySelector('[data-detail="unlink-how"]').textContent.replace(/\s+/g, ' '),
    'How: without an account claim: at sign-up, by the phone they entered, or by Link to this customer on this page.');
  assert.ok(!modal().textContent.includes('verified email'), modal().textContent);
});
