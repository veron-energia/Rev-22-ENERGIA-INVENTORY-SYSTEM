// The Class page in the app (the Owner, 27 Nov 2026; migration 548): the four class vouchers with their
// dates, who bought each (a unit of a voucher line is a seat), the date each seat chose (skin care: at
// most 6 a date) and who attended. The real page, menu, route and login guard against a fake backend;
// every name and phone is made up. The database decides who may do what; these tests are the page's part:
// it shows each role what it may do, sends the right calls and shows the database's sentence when it
// refuses.
//
// Run: node --test scripts/classes/tests/class-page.test.mjs
import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { REPO, setupDom, bundle, fakeSupabase, driver } from '../../ui/page-harness.mjs';
import { join } from 'node:path';

const dom = setupDom('https://energia.invalid/classes');
dom.window.matchMedia = () => ({ matches: false, addEventListener() {}, removeEventListener() {} });
dom.window.confirm = () => true;
const mod = await bundle(`
  import React from 'react';
  export { AuthProvider } from './src/context/AuthContext';
  export { Protected } from './src/components/RouteGuards';
  export { default as ClassPage } from './src/pages/ClassPage';
  export { BrowserRouter, Routes, Route } from 'react-router-dom';
  export { createRoot } from 'react-dom/client';
  export { act } from 'react';
  export { React };
`);
const { React, AuthProvider, Protected, ClassPage, BrowserRouter, Routes, Route } = mod;
const d = driver(mod, dom);
after(async () => { await d.unmount(); dom.window.close(); });
const h = React.createElement;

const app = () => h(AuthProvider, null, h(BrowserRouter, null, h(Routes, null,
  h(Route, { path: '/classes', element: h(Protected, null, h(ClassPage)) }))));

const SESSION = { access_token: 'x.y.z', user: { id: 'u-1', email: 'olive@class.invalid' } };
const S = (id, seq, date, over = {}) => ({ id, seq, title: `Session ${seq}`, kind: 'lesson', session_date: date, starts_at: '20:00:00', ends_at: '22:00:00',
  mode: 'zoom', venue: null, must_attend: false, taken: 0, ...over });
const CLASSES = [
  { voucher_id: 'v-found', code: 'EmiLymphatic', name: 'Lymphatic Foundation Workshop 2027', price: 799, is_active: true, seat_mode: 'all_sessions',
    capacity_per_date: null, sort_order: 1, summary: 'Monthly Zoom workshop: 12 sessions and a graduation', seats_sold: 3,
    details: { fee_note: 'Early bird S$799 (usual S$4,788)', time_text: 'Fridays, 8:00-10:00 PM', notes: ['Graduation: Sat 1 Jan 2028, 10:00 AM-3:00 PM, in person (venue to be confirmed).'] },
    sessions: [S('f1', 1, '2027-01-29', { mode: 'in_person', venue: 'The Adelphi', must_attend: true }), S('f2', 2, '2027-02-26'),
      S('fg', 13, '2028-01-01', { title: 'Graduation', kind: 'graduation', starts_at: '10:00:00', ends_at: '15:00:00', mode: 'in_person' })] },
  { voucher_id: 'v-adv', code: 'AdvancedZoom', name: 'Lymphatic Advanced Workshop 2027', price: 1441, is_active: true, seat_mode: 'all_sessions',
    capacity_per_date: null, sort_order: 2, summary: null, seats_sold: 0, details: {}, sessions: [] },
  { voucher_id: 'v-skin', code: 'KPopClass', name: 'Korea No.1 Skin Care Workshop', price: 676, is_active: true, seat_mode: 'choose_date',
    capacity_per_date: 6, sort_order: 3, summary: '1-day course, in person, max 6 per class', seats_sold: 3,
    details: { fee_note: 'S$676 (usual S$1,174 = course S$499 + Skin Care Set S$675)', venue_text: 'The Adelphi, 1 Coleman Street #B1-37', learn: ['Deep Cleansing', 'Intense Hydration', 'Restore & Protect'] },
    sessions: [S('k1', 1, '2027-01-27', { title: 'Class day', kind: 'class_day', mode: 'in_person', venue: 'The Adelphi, 1 Coleman Street #B1-37', starts_at: '19:00:00', ends_at: '21:00:00', taken: 6 }),
      S('k2', 2, '2027-02-24', { title: 'Class day', kind: 'class_day', mode: 'in_person', venue: 'The Adelphi, 1 Coleman Street #B1-37', starts_at: '19:00:00', ends_at: '21:00:00', taken: 1 })] },
  { voucher_id: 'v-lc', code: 'L-C', name: 'Lymphatic Class', price: 399, is_active: true, seat_mode: 'choose_date', capacity_per_date: null, sort_order: 4,
    summary: 'One in-person day of the Foundation class', seats_sold: 1, details: {}, sessions: [] },
];
const SEAT = (over) => ({ voucher_id: 'v-found', invoice_item_id: 'it-1', seat_no: 1, seats_on_line: 2, invoice_id: 'inv-1', invoice_no: 'INV-T-0001',
  invoice_status: 'paid', business_date: '2026-11-20', store_id: 'st-a', store_name: 'Test Store A', customer_id: 'c-1', customer_name: 'Alice Fixture',
  customer_phone: '+61 2 5550 1001', session_id: null, attended: [], ...over });
const SEATS = [
  SEAT({}), SEAT({ seat_no: 2, attended: ['f1'] }),
  SEAT({ voucher_id: 'v-skin', invoice_item_id: 'it-2', seat_no: 1, seats_on_line: 1, invoice_id: 'inv-2', invoice_no: 'INV-T-0002', customer_id: 'c-2',
    customer_name: 'Bob Fixture', customer_phone: 'LEGACY-NO-PHONE-CUST-123456', invoice_status: 'unpaid', session_id: 'k2', attended: [] }),
  SEAT({ voucher_id: 'v-skin', invoice_item_id: 'it-3', seat_no: 1, seats_on_line: 1, invoice_id: 'inv-3', invoice_no: 'INV-T-0003', customer_id: 'c-3',
    customer_name: 'Cara Fixture', customer_phone: '+61 2 5550 1003', session_id: null }),
];

let sb;
function signIn(role, { fail = {}, canEdit = role === 'owner' || role === 'manager', seats = SEATS } = {}) {
  sb = fakeSupabase({
    tables: {
      profiles: [{ id: 'u-1', full_name: 'Olive Test', role, is_active: true, email: 'olive@class.invalid', invitation_status: 'accepted', deleted_at: null }],
      user_store_assignments: [],
      stores: [{ id: 'st-a', name: 'Test Store A', code: 'TA', is_active: true, deleted_at: null }],
      vouchers: [{ id: 'v-found', name: 'Lymphatic Foundation Workshop 2027', code: 'EmiLymphatic', voucher_kind: 'normal', discount_amount: null, discount_percent: null,
        max_discount_cap: null, qty_type: 'unlimited', selling_price: 799, valid_from: null, valid_until: null, is_active: true, description: null, terms: null,
        deleted_at: null, reward_eligible: true, discount_category: null, birthday_rule: null }],
    },
    rpc: {
      class_page_data: () => ({ can_edit: canEdit, classes: structuredClone(CLASSES), seats: structuredClone(seats) }),
      class_choose_date: () => ({ changed: true }),
      class_set_attendance: () => ({ changed: true }),
      class_save_session: () => 'new-session',
      class_remove_session: () => ({ removed: true }),
      class_save_details: () => ({ ok: true }),
    },
    fail,
  });
  // The fake client has no .single(); the voucher window's save uses it.
  const from = sb.from;
  sb.from = t => {
    const q = from(t);
    // `single` is a flag of the fake's query, so the method is answered by a proxy.
    const px = new Proxy(q, { get: (o, k) => k === 'single' ? () => { o.maybeSingle(); return px; }
      : typeof o[k] === 'function' ? (...x) => { const r = o[k](...x); return r === o ? px : r; } : o[k] });
    return px;
  };
  sb.auth.session = SESSION;
  globalThis.__supabase = sb;
}
async function open(role, opts) {
  signIn(role, opts);
  history.replaceState(null, '', '/classes');
  await d.mount(app());
  await until(() => document.querySelector('h2')?.textContent === 'Class' && document.querySelector('[role=tablist]') || document.querySelector('[role=alert]') || /Access restricted/.test(d.text()), 'the Class page');
}
async function until(ok, what) {
  for (let i = 0; i < 40 && !ok(); i++) await d.tick(2);
  assert.ok(ok(), `${what}: ${d.text().slice(0, 300)}`);
}
const tabs = () => [...document.querySelectorAll('[role=tab]')];
const tab = name => tabs().find(t => t.textContent === name);
const seatRows = () => [...document.querySelectorAll('[data-testid=class-seat]')];
const rowText = r => r.textContent.replace(/\s+/g, ' ').trim();
const calls = name => sb.calls.filter(c => c.rpc === name);
const btn = (label) => d.button(label);

test('staff: the four classes in order, the first one with its details, dates and buyers', async () => {
  await open('staff');
  assert.deepEqual(tabs().map(t => t.textContent), ['Lymphatic Foundation Workshop 2027', 'Lymphatic Advanced Workshop 2027', 'Korea No.1 Skin Care Workshop', 'Lymphatic Class']);
  assert.equal(tab('Lymphatic Foundation Workshop 2027').getAttribute('aria-selected'), 'true');
  const t = d.text();
  for (const s of ['S$799', 'Early bird S$799 (usual S$4,788)', 'Fridays, 8:00-10:00 PM', 'Graduation: Sat 1 Jan 2028', '3 seats sold (all stores)']) assert.ok(t.includes(s), s);
  const dates = [...document.querySelectorAll('[data-testid=class-sessions] tbody tr')].map(rowText);
  assert.equal(dates.length, 3);
  assert.ok(dates[0].startsWith('Fri 29 Jan 2027Session 1') && dates[0].includes('Must attend') && dates[0].includes('8:00 PM – 10:00 PM') && dates[0].includes('In person · The Adelphi'), dates[0]);
  assert.ok(dates[1].startsWith('Fri 26 Feb 2027') && dates[1].includes('Zoom'), dates[1]);
  assert.ok(dates[2].startsWith('Sat 1 Jan 2028') && dates[2].includes('Graduation') && dates[2].includes('10:00 AM – 3:00 PM') && dates[2].includes('venue to be confirmed'), dates[2]);
  assert.equal(seatRows().length, 2);
  assert.ok(rowText(seatRows()[0]).includes('Alice Fixture') && rowText(seatRows()[0]).includes('+61 2 5550 1001') && rowText(seatRows()[0]).includes('INV-T-0001')
    && rowText(seatRows()[0]).includes('Paid · Test Store A') && rowText(seatRows()[0]).includes('1 of 2'), rowText(seatRows()[0]));
});

test('staff cannot edit: no Add date, Edit details, Change or Remove buttons', async () => {
  await open('staff');
  assert.equal(btn('Add date'), undefined);
  assert.equal(btn('Edit details'), undefined);
  assert.equal(document.querySelectorAll('[aria-label^="Edit "], [aria-label^="Remove "]').length, 0);
});

test('an Owner and a Manager see the editing buttons', async () => {
  for (const role of ['owner', 'manager']) {
    await open(role);
    assert.ok(btn('Add date') && btn('Edit details'), role);
    assert.equal(document.querySelectorAll('[aria-label^="Edit "]').length, 3, role);
    assert.equal(document.querySelectorAll('[aria-label^="Remove "]').length, 3, role);
  }
});

test('an Admin (the database says no edits) sees none, whatever the role names: the page follows can_edit', async () => {
  await open('admin', { canEdit: false });
  assert.equal(btn('Add date'), undefined);
});

test('an Inventory Manager gets no page and the database is never asked', async () => {
  await open('inventory_manager');
  assert.ok(/Access restricted/.test(d.text()) && /works with stock only/.test(d.text()));
  assert.equal(calls('class_page_data').length, 0);
  assert.equal(tabs().length, 0);
});

test('an all-sessions class: tick attendance for a session; the box shows who attended it', async () => {
  await open('staff');
  const sel = document.getElementById('class-tick-session');
  assert.ok(sel, 'the session to tick is chosen at the top');
  const boxes = () => [...document.querySelectorAll('[data-testid=class-seat] input[type=checkbox]')];
  await d.setValue(sel, 'f1');
  assert.deepEqual(boxes().map(b => b.checked), [false, true], 'seat 2 attended Session 1');
  await d.toggle(boxes()[0]);
  assert.deepEqual(calls('class_set_attendance').map(c => c.args), [{ p_session_id: 'f1', p_invoice_item_id: 'it-1', p_seat_no: 1, p_attended: true }]);
  await d.setValue(document.getElementById('class-tick-session'), 'f2');
  assert.deepEqual(boxes().map(b => b.checked), [false, false], 'nobody attended Session 2');
});

test('skin care: each seat chooses one date; a full date is not offered; the capacity shows', async () => {
  await open('staff');
  await d.click(tab('Korea No.1 Skin Care Workshop'));
  const t = d.text();
  assert.ok(t.includes('At most 6 seats on each date') && t.includes('Deep Cleansing · Intense Hydration · Restore & Protect'));
  const dates = [...document.querySelectorAll('[data-testid=class-sessions] tbody tr')].map(rowText);
  assert.ok(dates[0].includes('Wed 27 Jan 2027') && dates[0].includes('6 of 6') && dates[0].includes('Full'), dates[0]);
  assert.ok(dates[1].includes('1 of 6') && !dates[1].includes('Full'), dates[1]);
  const [bob, cara] = seatRows();
  assert.ok(rowText(bob).includes('Unpaid · Test Store A') && !rowText(bob).includes('LEGACY'), 'a placeholder phone is not shown: ' + rowText(bob));
  assert.ok(rowText(cara).includes('+61 2 5550 1003'));
  const selCara = cara.querySelector('select');
  const opts = [...selCara.options].map(o => ({ v: o.value, t: o.textContent, off: o.disabled }));
  assert.deepEqual(opts.map(o => o.t), ['Not chosen yet', 'Wed 27 Jan 2027 · 6 of 6 (full)', 'Wed 24 Feb 2027 · 1 of 6']);
  assert.equal(opts[1].off, true, 'the full date is disabled');
  assert.equal(selCara.value, '');
  const selBob = bob.querySelector('select');
  assert.equal(selBob.value, 'k2', 'Bob chose 24 Feb');
  await d.setValue(selCara, 'k2');
  assert.deepEqual(calls('class_choose_date').map(c => c.args), [{ p_invoice_item_id: 'it-3', p_seat_no: 1, p_session_id: 'k2' }]);
  // Clearing a date sends null.
  await d.setValue(document.querySelector('[data-testid=class-seat]:nth-child(1) select'), '');
  assert.deepEqual(calls('class_choose_date').at(-1).args, { p_invoice_item_id: 'it-2', p_seat_no: 1, p_session_id: null });
  // A seat with no date cannot be ticked; one with a date can.
  const boxes = [...document.querySelectorAll('[data-testid=class-seat] input[type=checkbox]')];
  assert.equal(boxes[1].disabled, true);
});

test('skin care: ticking a seat attended sends its own date', async () => {
  await open('staff');
  await d.click(tab('Korea No.1 Skin Care Workshop'));
  const box = document.querySelector('[data-testid=class-seat] input[type=checkbox]');
  assert.equal(box.disabled, false);
  await d.toggle(box);
  assert.deepEqual(calls('class_set_attendance').at(-1).args, { p_session_id: 'k2', p_invoice_item_id: 'it-2', p_seat_no: 1, p_attended: true });
});

test('the database refusing a date (full, or another store) is shown in its own words, and nothing else changes', async () => {
  await open('staff', { fail: { class_choose_date: 'That date is full: 6 of 6 seats are taken.' } });
  await d.click(tab('Korea No.1 Skin Care Workshop'));
  await d.setValue(seatRows()[1].querySelector('select'), 'k2');
  await until(() => document.querySelector('[role=alert]'), 'the refusal');
  assert.ok(document.querySelector('[role=alert]').textContent.includes('That date is full: 6 of 6 seats are taken.'));
});

test('the Lymphatic Class has no dates yet: it says so, and Owners and Managers can add one', async () => {
  await open('staff');
  await d.click(tab('Lymphatic Class'));
  assert.ok(d.text().includes('No dates yet. An Owner or Manager adds them.'));
  await open('owner');
  await d.click(tab('Lymphatic Class'));
  assert.ok(d.text().includes('Add the dates a seat can choose from.'));
  await d.click(btn('Add date'));
  await d.setValue(document.getElementById('cs-date'), '2027-02-06');
  await d.setValue(document.getElementById('cs-title'), 'In-person day');
  await d.setValue(document.getElementById('cs-start'), '10:00');
  await d.setValue(document.getElementById('cs-end'), '17:00');
  await d.setValue(document.getElementById('cs-venue'), 'The Adelphi');
  await d.click(btn('Save'));
  const call = calls('class_save_session').at(-1);
  assert.deepEqual(call.args, { p_voucher_id: 'v-lc', p_session_id: null, p_data: { title: 'In-person day', kind: 'class_day', session_date: '2027-02-06',
    starts_at: '10:00', ends_at: '17:00', mode: 'in_person', venue: 'The Adelphi', must_attend: false } });
});

test('a date needs its day: the form says so before asking the database', async () => {
  await open('owner');
  await d.click(btn('Add date'));
  await d.click(btn('Save'));
  assert.ok(d.text().includes('Choose the day.'));
  assert.equal(calls('class_save_session').length, 0);
});

test('Owner changes and removes a date', async () => {
  await open('manager');
  await d.click(document.querySelector('[aria-label="Edit Fri 26 Feb 2027"]'));
  assert.equal(document.getElementById('cs-date').value, '2027-02-26');
  await d.setValue(document.getElementById('cs-date'), '2027-02-27');
  await d.click(btn('Save'));
  const call = calls('class_save_session').at(-1);
  assert.equal(call.args.p_session_id, 'f2');
  assert.equal(call.args.p_data.session_date, '2027-02-27');
  await d.click(document.querySelector('[aria-label="Remove Fri 26 Feb 2027"]'));
  assert.deepEqual(calls('class_remove_session').at(-1).args, { p_session_id: 'f2' });
});

test('Owner edits the details and the capacity of skin care', async () => {
  await open('owner');
  await d.click(tab('Korea No.1 Skin Care Workshop'));
  await d.click(btn('Edit details'));
  assert.equal(document.getElementById('cd-cap').value, '6');
  await d.setValue(document.getElementById('cd-cap'), 'six');
  await d.click(btn('Save'));
  assert.ok(d.text().includes('whole number of seats'));
  assert.equal(calls('class_save_details').length, 0);
  await d.setValue(document.getElementById('cd-cap'), '8');
  await d.setValue(document.getElementById('cd-summary'), 'One day, in person');
  await d.click(btn('Save'));
  const a = calls('class_save_details').at(-1).args;
  assert.equal(a.p_voucher_id, 'v-skin');
  assert.equal(a.p_data.summary, 'One day, in person');
  assert.equal(a.p_data.capacity_per_date, 8);
  assert.deepEqual(a.p_data.details.learn, ['Deep Cleansing', 'Intense Hydration', 'Restore & Protect']);
});

test('a database without 548: the page says it could not load, and the page does not break', async () => {
  await open('owner', { fail: { class_page_data: 'Could not find the function public.class_page_data without parameters in the schema cache' } });
  assert.ok(d.text().includes('The Class page could not be loaded: Could not find the function'));
});

test('search narrows the buyers by name, phone or invoice number', async () => {
  await open('staff');
  await d.click(tab('Korea No.1 Skin Care Workshop'));
  await d.setValue(document.querySelector('[aria-label="Search buyers"]'), 'cara');
  assert.equal(seatRows().length, 1);
  await d.setValue(document.querySelector('[aria-label="Search buyers"]'), 'INV-T-0002');
  assert.equal(seatRows().length, 1);
  assert.ok(rowText(seatRows()[0]).includes('Bob Fixture'));
  await d.setValue(document.querySelector('[aria-label="Search buyers"]'), 'nobody');
  assert.ok(d.text().includes('No buyer matches the search.'));
});

test('the menu has Class next to Vouchers for every role but an Inventory Manager, and App.tsx routes /classes', async () => {
  const layout = readFileSync(join(REPO, 'src/components/AppLayout.tsx'), 'utf8');
  assert.match(layout, /\{ to: '\/vouchers', label: 'Vouchers'[^\n]*\n[^\n]*\n[^\n]*\n\s*\{ to: '\/classes', label: 'Class', icon: <GraduationCap size=\{17\} \/>, show: !worksWithStockOnly\(role\) \}/);
  const app = readFileSync(join(REPO, 'src/App.tsx'), 'utf8');
  assert.match(app, /<Route path="\/classes" element=\{<Protected><ClassPage \/><\/Protected>\} \/>/);
  assert.match(app, /const ClassPage = lazyPage\(\(\) => import\('\.\/pages\/ClassPage'\)\)/);
});

test('the four vouchers left the Vouchers page: Owners and Managers edit them here, with the Vouchers page\'s own window and Prices', async () => {
  for (const role of ['owner', 'manager']) {
    await open(role);
    assert.ok(btn('Edit voucher') && btn('Prices'), role);
  }
  await open('owner');
  await d.click(btn('Edit voucher'));
  assert.equal(document.querySelector('.modal h3, [data-modal-overlay] h3')?.textContent, 'Edit Voucher');
  const name = [...document.querySelectorAll('input')].find(i => i.value === 'Lymphatic Foundation Workshop 2027');
  assert.ok(name, 'the window holds the voucher as it is');
  await d.setValue(name, 'Lymphatic Foundation Workshop 2027 (new)');
  await d.click(btn('Save'));
  const upd = sb.calls.find(c => c.table === 'vouchers' && c.op === 'update');
  assert.ok(upd, 'saved with the Vouchers page\'s own write: an update of vouchers');
  assert.equal(upd.payload.name, 'Lymphatic Foundation Workshop 2027 (new)');
  assert.deepEqual(upd.filters, [{ c: 'id', v: 'v-found' }]);
  assert.equal(upd.payload.selling_price, 799);
  assert.equal(calls('set_voucher_price_all_stores').length, 0, 'store prices untouched unless ticked');
  assert.equal(calls('class_page_data').length >= 2, true, 'the page reloads after the save');
  await d.click(btn('Prices'));
  assert.ok(d.text().includes('Store Prices — Lymphatic Foundation Workshop 2027'), 'the same store-price editor');
});

test('staff and an Inventory Manager get no Edit voucher or Prices here (the Vouchers page is for Owners and Managers)', async () => {
  await open('staff');
  assert.equal(btn('Edit voucher'), undefined);
  assert.equal(btn('Prices'), undefined);
});
