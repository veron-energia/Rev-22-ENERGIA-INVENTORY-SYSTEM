/**
 * The payment QR pop-up on an invoice, mounted for real (Owner, 6 Oct 2026).
 *
 * The real pop-up, picker, instalment fields and invoice Modal are bundled and
 * mounted in jsdom, wired the way Record Payment wires them: picking PayNow,
 * GrabPay or Atome shows the store's QR at once, Show QR brings it back, and
 * Escape closes the pop-up without closing the invoice behind it. Store ids and
 * images are invented; the invoice number is a placeholder.
 *
 * Run: node --test scripts/invoices/tests/payment-qr-popup.test.mjs
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { build } from 'esbuild';
import { JSDOM } from 'jsdom';

const built = await build({
  stdin: {
    contents: `
      import React from 'react';
      import { createRoot } from 'react-dom/client';
      import { Modal } from './src/components/ui';
      import { InvoiceSearchSelect } from './src/components/invoices/InvoiceSearchSelect';
      import { InstalmentPortionFields } from './src/components/invoices/InstalmentPortionFields';
      import { PaymentQrPopup, PaymentQrLineAction } from './src/components/invoices/PaymentQrPopup';
      import { paymentQrFor } from './src/lib/invoices/paymentQr.mjs';

      const METHODS = [
        { id: 'm-cash', name: 'Cash' },
        { id: 'm-paynow', name: 'PayNow' },
        { id: 'm-grab', name: 'GrabPay Full Payment' },
        { id: 'm-atome', name: 'Atome' },
        { id: 'm-hitpay', name: 'HitPay (online)' },
        { id: 'm-wallet', name: 'Wallet — Paid Credit', is_wallet_credit: true },
      ];
      const img = k => 'https://assets.invalid/store-assets/main/' + k + '.png';
      const MAIN = { id: 'store-main', name: 'Energia Rev 22 (Adelphi)', is_active: true, deleted_at: null,
        created_at: '2026-07-03T07:35:38Z', qr_paynow_url: img('paynow'), qr_grabpay_url: img('grabpay'), qr_atome_url: img('atome') };
      const VAN = { id: 'store-van', name: 'Energia Van & RoadShow', is_active: true, deleted_at: null,
        created_at: '2026-07-30T04:10:44Z', qr_paynow_url: null, qr_grabpay_url: null, qr_atome_url: null };

      window.__events = { invoiceClosed: 0, qrClosed: 0, confirms: 0 };
      window.confirm = () => { window.__events.confirms++; return true; };

      function Harness({ storeId, amount, noPayNowAnywhere, confirmClose, noReturnFocus }) {
        const stores = noPayNowAnywhere ? [{ ...MAIN, qr_paynow_url: null }, VAN] : [MAIN, VAN];
        const qrFor = id => paymentQrFor(METHODS.find(m => m.id === id), storeId, stores);
        const [open, setOpen] = React.useState(true);
        const [method, setMethod] = React.useState('');
        const [real, setReal] = React.useState('');
        const [qr, setQr] = React.useState(null);
        const show = (id, instalment) => { if (qrFor(id)?.image) setQr({ id, instalment }); };
        const showing = qr ? qrFor(qr.id) : null;
        // As Record Payment does: focus goes back to the line's Show QR, else its picker.
        const row = React.useRef(null);
        const buttons = React.useRef(new Map());
        const buttonRef = instalment => el => { if (el) buttons.current.set(instalment, el); else buttons.current.delete(instalment); };
        const returnFocusTo = () => buttons.current.get(qr.instalment) ?? row.current?.querySelector('.invoice-search-select > button');
        if (!open) return <p id="invoice-closed">closed</p>;
        return <>
          <Modal title="Invoice INV-TEST-0001" wide confirmClose={confirmClose}
            onClose={() => { window.__events.invoiceClosed++; setOpen(false); }}>
            <div className="invoice-payment-row" ref={row}>
              <InvoiceSearchSelect value={method} placeholder="Select payment method"
                options={METHODS.map(m => ({ value: m.id, label: m.name }))}
                onChange={id => { setMethod(id); show(id, false); }} />
              <PaymentQrLineAction qr={qrFor(method)} buttonRef={buttonRef(false)} onShow={() => show(method, false)} />
            </div>
            <InstalmentPortionFields value={{ method_id: real, months: 12 }} methods={METHODS}
              onChange={v => setReal(v.method_id)} receivedNow={amount} onReceivedNow={() => {}}
              onMethodPicked={id => show(id, true)}
              methodAside={<PaymentQrLineAction qr={qrFor(real)} buttonRef={buttonRef(true)} onShow={() => show(real, true)} />} />
          </Modal>
          {showing?.image && <PaymentQrPopup qr={showing} image={showing.image} amount={amount}
            reference="INV-TEST-0001" onClose={() => { window.__events.qrClosed++; setQr(null); }}
            returnFocusTo={noReturnFocus ? undefined : returnFocusTo} />}
        </>;
      }
      window.__mount = props => createRoot(document.getElementById('root')).render(<Harness {...props} />);
    `,
    resolveDir: process.cwd(), loader: 'tsx',
  },
  bundle: true, write: false, format: 'iife', jsx: 'automatic',
  loader: { '.css': 'empty' },
  // ui.tsx reads the signed-in role through AuthContext, which imports the
  // Supabase client. Nothing here calls the server.
  plugins: [{
    name: 'stub-supabase',
    setup(b) {
      b.onResolve({ filter: /(^|\/)lib\/supabase$/ }, () => ({ path: 'supabase-stub', namespace: 'stub' }));
      b.onLoad({ filter: /.*/, namespace: 'stub' }, () => ({
        contents: `export const supabase = new Proxy({}, { get() { throw new Error('the QR pop-up queried the server'); } });`,
        loader: 'js',
      }));
    },
  }],
});
const bundle = built.outputFiles[0].text;

async function mount(props = {}) {
  const dom = new JSDOM('<!doctype html><div id="root"></div>', { runScripts: 'dangerously', pretendToBeVisual: true });
  const w = dom.window;
  const script = w.document.createElement('script');
  script.textContent = bundle;
  w.document.body.appendChild(script);
  w.__mount({ storeId: 'store-main', amount: 123.45, confirmClose: false, ...props });
  await settle();
  return w;
}
const settle = () => new Promise(r => setTimeout(r, 40));
const popup = w => w.document.querySelector('.invoice-qr[role=dialog]');
const invoice = w => w.document.querySelector('.modal[role=dialog]');
const key = (w, el, k, extra = {}) =>
  el.dispatchEvent(new w.KeyboardEvent('keydown', { key: k, bubbles: true, cancelable: true, ...extra }));

/** Choose a method the way staff do: open the picker, press the option. */
async function pick(w, label, name) {
  w.document.querySelector(`button[aria-label="${label}"]`).click(); await settle();
  const option = [...w.document.querySelectorAll('[role=option]')].find(o => o.textContent === name);
  assert.ok(option, `${name} is not offered`);
  option.click(); await settle();
}

test('picking PayNow shows the store’s QR at once, with the amount and the invoice number', async () => {
  const w = await mount();
  assert.ok(!popup(w), 'nothing pops up before a method is picked');
  await pick(w, 'Payment method', 'PayNow');
  const p = popup(w);
  assert.ok(p, 'PayNow must pop the QR up the moment it is picked');
  assert.equal(p.querySelector('h3').textContent, 'Scan to pay with PayNow');
  assert.equal(p.querySelector('.invoice-qr-amount').textContent, 'Pay S$123.45');
  assert.equal(p.querySelector('.invoice-qr-ref').textContent, 'Reference: INV-TEST-0001');
  const image = p.querySelector('img');
  assert.equal(image.getAttribute('src'), 'https://assets.invalid/store-assets/main/paynow.png');
  assert.match(image.getAttribute('alt'), /PayNow QR code of Energia Rev 22 \(Adelphi\)/);
  assert.ok(!p.querySelector('.invoice-qr-borrowed'), 'the store’s own QR needs no note');
  assert.equal(w.document.activeElement?.textContent, 'Customer has paid', 'focus moves into the pop-up');
  assert.match(p.textContent, /This records nothing/);
});

test('Escape closes the pop-up and leaves the invoice open', async () => {
  const w = await mount({ confirmClose: true });
  await pick(w, 'Payment method', 'PayNow');
  key(w, w.document.activeElement, 'Escape');
  await settle();
  assert.ok(!popup(w), 'Escape must close the pop-up');
  assert.ok(invoice(w), 'Escape on the pop-up closed the invoice behind it');
  assert.deepEqual({ ...w.__events }, { invoiceClosed: 0, qrClosed: 1, confirms: 0 },
    'the invoice must not even ask whether to discard');
});

test('Escape reaches only the pop-up wherever focus happens to be', async () => {
  const w = await mount();
  await pick(w, 'Payment method', 'PayNow');
  key(w, w.document.body, 'Escape');
  await settle();
  assert.ok(!popup(w));
  assert.ok(invoice(w));
  assert.equal(w.__events.invoiceClosed, 0);
});

test('with the pop-up gone, Escape closes the invoice as it always did', async () => {
  const w = await mount();
  await pick(w, 'Payment method', 'PayNow');
  key(w, w.document.activeElement, 'Escape'); await settle();
  key(w, w.document.body, 'Escape'); await settle();
  assert.ok(!invoice(w), 'the invoice Modal’s own Escape must still work');
  assert.equal(w.__events.invoiceClosed, 1);
  assert.ok(w.document.getElementById('invoice-closed'));
});

test('Customer has paid and Close only close the pop-up; Show QR brings it back', async () => {
  const w = await mount();
  await pick(w, 'Payment method', 'PayNow');
  const show = () => w.document.querySelector('.invoice-qr-show');
  assert.ok(show(), 'a QR line offers Show QR');
  [...popup(w).querySelectorAll('button')].find(b => b.textContent === 'Customer has paid').click(); await settle();
  assert.ok(!popup(w)); assert.ok(invoice(w));
  // jsdom does not focus a button it clicks; a keyboard user's would be.
  show().focus(); show().click(); await settle();
  assert.ok(popup(w), 'Show QR must reopen it');
  [...popup(w).querySelectorAll('button')].find(b => b.textContent === 'Close').click(); await settle();
  assert.ok(!popup(w)); assert.ok(invoice(w));
  assert.ok(w.document.activeElement === show(), 'focus goes back to Show QR');
  show().click(); await settle();
  w.document.querySelector('.invoice-qr-backdrop').click(); await settle();
  assert.ok(!popup(w), 'a press outside closes it');
  assert.equal(w.__events.invoiceClosed, 0);
});

/** Choose by keyboard: open the picker, type part of the name, press Enter. */
async function pickByKeyboard(w, label, typed) {
  w.document.querySelector(`button[aria-label="${label}"]`).click(); await settle();
  const input = w.document.activeElement;
  assert.equal(input?.getAttribute('role'), 'combobox', 'the picker’s search box takes focus');
  Object.getOwnPropertyDescriptor(w.HTMLInputElement.prototype, 'value').set.call(input, typed);
  input.dispatchEvent(new w.Event('input', { bubbles: true })); await settle();
  key(w, input, 'Enter'); await settle();
}
const paidButton = w => [...popup(w).querySelectorAll('button')].find(b => b.textContent === 'Customer has paid');

test('closing a QR opened by a keyboard pick puts focus on that line’s Show QR, not the page', async () => {
  const w = await mount();
  await pickByKeyboard(w, 'Payment method', 'payn');
  assert.ok(popup(w), 'Enter on PayNow pops it up');
  key(w, w.document.activeElement, 'Escape'); await settle();
  assert.ok(!popup(w)); assert.ok(invoice(w));
  assert.notEqual(w.document.activeElement, w.document.body, 'focus fell back to the page behind the invoice');
  assert.ok(w.document.activeElement === w.document.querySelector('.invoice-payment-row .invoice-qr-show'),
    'focus goes to the line’s Show QR');
});

test('closing a QR opened by a mouse pick puts focus on that line’s Show QR', async () => {
  const w = await mount();
  w.document.querySelector('button[aria-label="Payment method"]').click(); await settle();
  // Chrome focuses an option button as it is pressed; the list then closes under it.
  const option = [...w.document.querySelectorAll('[role=option]')].find(o => o.textContent === 'PayNow');
  option.focus(); option.click(); await settle();
  paidButton(w).click(); await settle();
  assert.ok(!popup(w));
  assert.ok(w.document.activeElement === w.document.querySelector('.invoice-payment-row .invoice-qr-show'));
});

test('closing an instalment’s QR puts focus on the Show QR beside its real method', async () => {
  const w = await mount();
  await pickByKeyboard(w, 'Actual payment method', 'atome');
  assert.ok(popup(w));
  [...popup(w).querySelectorAll('button')].find(b => b.textContent === 'Close').click(); await settle();
  assert.ok(!popup(w));
  assert.ok(w.document.activeElement === w.document.querySelector('.instalment-method .invoice-qr-show'));
});

test('with no return target the pop-up hands focus back to what opened it', async () => {
  const w = await mount({ noReturnFocus: true });
  await pick(w, 'Payment method', 'PayNow');
  paidButton(w).click(); await settle();
  const show = w.document.querySelector('.invoice-qr-show');
  show.focus(); show.click(); await settle();
  assert.ok(popup(w));
  key(w, w.document.activeElement, 'Escape'); await settle();
  assert.ok(w.document.activeElement === show);
});

test('Tab stays inside the pop-up', async () => {
  const w = await mount();
  await pick(w, 'Payment method', 'PayNow');
  const buttons = [...popup(w).querySelectorAll('button')];
  buttons.at(-1).focus();
  key(w, buttons.at(-1), 'Tab');
  assert.ok(w.document.activeElement === buttons[0], 'Tab from the last button goes to the first');
  key(w, buttons[0], 'Tab', { shiftKey: true });
  assert.ok(w.document.activeElement === buttons.at(-1), 'Shift+Tab from the first goes to the last');
});

test('other methods never pop up and offer no Show QR', async () => {
  for (const name of ['Cash', 'HitPay (online)', 'Wallet — Paid Credit']) {
    const w = await mount();
    await pick(w, 'Payment method', name);
    assert.ok(!popup(w), `${name} popped up a QR`);
    assert.ok(!w.document.querySelector('.invoice-qr-show'), `${name} offered Show QR`);
    assert.ok(!w.document.querySelector('.invoice-qr-missing'));
  }
});

test('a store with none shows another store’s QR and names it', async () => {
  const w = await mount({ storeId: 'store-van' });
  await pick(w, 'Payment method', 'GrabPay Full Payment');
  const p = popup(w);
  assert.equal(p.querySelector('h3').textContent, 'Scan to pay with GrabPay');
  assert.equal(p.querySelector('.invoice-qr-method').textContent, 'GrabPay Full Payment');
  assert.equal(p.querySelector('img').getAttribute('src'), 'https://assets.invalid/store-assets/main/grabpay.png');
  assert.match(p.querySelector('.invoice-qr-borrowed').textContent,
    /This store has no GrabPay QR of its own, so this is Energia Rev 22 \(Adelphi\)'s\./);
});

test('when no store has the image nothing pops up, and the line says so quietly', async () => {
  const w = await mount({ noPayNowAnywhere: true });
  await pick(w, 'Payment method', 'PayNow');
  assert.ok(!popup(w));
  assert.ok(!w.document.querySelector('.invoice-qr-show'));
  assert.equal(w.document.querySelector('.invoice-qr-missing')?.textContent, 'No PayNow QR uploaded');
});

test('an instalment’s real method pops up its QR too', async () => {
  const w = await mount();
  await pick(w, 'Actual payment method', 'Atome');
  const p = popup(w);
  assert.ok(p, 'Atome as the real method of an instalment must pop up');
  assert.equal(p.querySelector('h3').textContent, 'Scan to pay with Atome');
  assert.ok(w.document.querySelector('.instalment-method .invoice-qr-show'), 'Show QR sits beside the real method');
  key(w, w.document.activeElement, 'Escape'); await settle();
  assert.ok(!popup(w)); assert.ok(invoice(w));
});

test('a line with no amount yet says so instead of S$0.00', async () => {
  const w = await mount({ amount: 0 });
  await pick(w, 'Payment method', 'PayNow');
  assert.equal(popup(w).querySelector('.invoice-qr-amount').textContent, 'No amount entered on this line yet');
});

test('an image that will not load says what to do', async () => {
  const w = await mount();
  await pick(w, 'Payment method', 'PayNow');
  popup(w).querySelector('img').dispatchEvent(new w.Event('error'));
  await settle();
  assert.ok(!popup(w).querySelector('img'));
  assert.match(popup(w).querySelector('[role=alert]').textContent, /could not be loaded.*Stores page/);
});

// Record Payment itself is too large to mount here; these hold its wiring to
// what the harness above does.
const page = readFileSync(new URL('../../../src/pages/InvoicesPage.tsx', import.meta.url), 'utf8');
const panel = readFileSync(new URL('../../../src/components/invoices/InstalmentPortionFields.tsx', import.meta.url), 'utf8');

test('Record Payment pops the QR on an explicit pick and offers Show QR on both pickers', () => {
  assert.match(page, /onChange=\{id => \{ setPayLines\([^\n]*payment_method_id: id[^\n]*\); showPayQr\(i, id, false\); \}\}/,
    'the method picker must open the QR the moment a method is picked');
  assert.match(page, /onMethodPicked=\{id => showPayQr\(i, id, true\)\}/, 'the instalment’s real method must too');
  assert.equal((page.match(/<PaymentQrLineAction /g) ?? []).length, 2, 'Show QR beside a line’s method and an instalment’s');
  assert.match(page, /paymentQrFor\(methods\.find\(m => m\.id === methodId\), detail\?\.store_id, stores\)/,
    'the QR is the open invoice’s store’s');
  assert.match(page, /reference=\{detail\.invoice_no\}/);
  assert.match(page, /returnFocusTo=\{\(\) => payQrReturnFocus\(payQrView\.line, payQrView\.instalment\)\}/,
    'a closing QR hands focus back to its own line');
  assert.match(page, /buttonRef=\{payQrButtonRef\(i, false\)\}[\s\S]*buttonRef=\{payQrButtonRef\(i, true\)\}/,
    'both Show QR buttons are where focus returns');
  assert.match(page, /className="invoice-payment-row" ref=\{el => \{ payLineRows\.current\[i\] = el; \}\}/,
    'the line’s picker is the fallback');
  assert.match(panel, /onChange=\{id => \{ onChange\(\{ \.\.\.value, method_id: id \}\); onMethodPicked\?\.\(id\); \}\}/);
});

test('saving a payment is untouched by the pop-up', () => {
  const pay = page.slice(page.indexOf('const handlePay = async'), page.indexOf('const handlePay = async') + 6000);
  assert.doesNotMatch(pay, /payQr|PaymentQr/, 'Record Payment must not depend on the QR');
  assert.match(page, /!!quickCustomerFor \|\| !!payQrView;/, 'an open QR holds back a live reload of the invoice');
});
