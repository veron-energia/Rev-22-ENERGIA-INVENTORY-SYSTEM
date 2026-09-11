// The invoice detail actions, payment entry and correction form, driven as a
// person would drive them. Real components, in-memory fixtures, no network and
// no credentials.
import { build } from 'esbuild';
import { createRequire } from 'node:module';
import { readFile, mkdir } from 'node:fs/promises';
import assert from 'node:assert/strict';
const require = createRequire(import.meta.url);
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || '/Users/shinthantaungstanley/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
await mkdir('.invoice-test/browser', { recursive: true });

const date = '2026-09-01T01:00:00Z';
const common = { is_active: true, deleted_at: null };
const base = {
  stores: [{ id: 'store', name: 'Test Store', code: 'TEST', ...common }],
  customers: [{ id: 'customer', full_name: 'Test Customer', phone: '+6591234567', ...common }],
  profiles: [{ id: 'owner', full_name: 'Test Owner', role: 'owner', ...common }],
  products: [{ id: 'socks', name: 'Long Energia Socks', sku: 'SOCK', product_type: 'own', ...common }],
  store_product_prices: [{ store_id: 'store', product_id: 'socks', selling_price: 100, member_price: 100, non_member_price: 100, availability: 'available', ...common }],
  store_inventory: [{ store_id: 'store', product_id: 'socks', current_qty: 100 }],
  payment_methods: [
    { id: 'cash', name: 'Cash', ...common },
    { id: 'bank', name: 'Bank Transfer', ...common },
  ],
  invoice_promotion_selections: [], promotions: [], promotion_store_prices: [],
  promotion_choice_groups: [], promotion_choice_options: [], promotion_items: [],
};
const invoice = (over = {}) => ({
  id: 'invoice', invoice_no: 'INV-TEST', store_id: 'store', customer_id: 'customer',
  subtotal: 100, total_amount: 100, discount_total: 0, manual_discount: 0,
  created_at: date, business_date: '2026-09-01', created_by: 'owner', edit_count: 0,
  ...common, ...over,
});
const line = { id: 'line', invoice_id: 'invoice', line_kind: 'product', product_id: 'socks', quantity: 1, unit_price: 100, line_total: 100, topup_amount: 0, foc_quantity: 0 };

/* Scenarios differ only in the invoice's recorded state, which is the point:
 * the interface must decide what to offer from that, not from a status name. */
const scenarios = {
  paid: {
    tables: { ...base, invoices: [invoice({ status: 'paid', paid_amount: 100, paid_at: date,
      instalment_category: 'in_house', instalment_method_id: 'bank', instalment_months: 6 })], invoice_items: [line],
      invoice_payments: [{ id: 'payment', invoice_id: 'invoice', payment_method_id: 'cash', amount: 100, created_at: date, entry_kind: 'receipt' }] },
    financial: { total: 100, net_received: 100, outstanding: 0, refund_due: 0, refunded: 0, status: 'paid' },
  },
  unpaid: {
    tables: { ...base, invoices: [invoice({ status: 'unpaid', paid_amount: 0 })], invoice_items: [line], invoice_payments: [] },
    financial: { total: 100, net_received: 0, outstanding: 100, refund_due: 0, refunded: 0, status: 'unpaid' },
  },
  // Fully refunded: the paid amount is back at zero, and this must NOT be
  // mistaken for an ordinary unpaid invoice.
  refunded: {
    tables: { ...base, invoices: [invoice({ status: 'refunded', paid_amount: 0, paid_at: date })], invoice_items: [line],
      invoice_payments: [{ id: 'payment', invoice_id: 'invoice', payment_method_id: 'cash', amount: 100, created_at: date, entry_kind: 'receipt' }] },
    financial: { total: 100, net_received: 0, outstanding: 0, refund_due: 0, refunded: 100, status: 'refunded' },
  },
};

const mock = `export const supabase={ from(table) {
 let rows=[...(window.__tables[table]||[])], one=false;
 const q=new Proxy({}, {get(_,key) {
  if(key==='then') return (ok,bad)=>Promise.resolve(
    window.__failInvoiceReload && table==='invoices' && one
      ? {data:null,error:{message:'Network error while reloading the invoice'}}
      : {data:one?(rows[0]||null):rows,error:null}).then(ok,bad);
  return (...args)=>{if(key==='eq')rows=rows.filter(r=>r[args[0]]===args[1]);if(key==='in')rows=rows.filter(r=>args[1].includes(r[args[0]]));if(key==='single'||key==='maybeSingle')one=true;return q;};
 }}); return q;
 }, rpc(name,args) {
 window.__calls.push({name,args});
 let data=[];
 if(name==='invoice_effective_affiliate')data={found:true,has_affiliate:false};
 if(name==='customer_search')data=window.__tables.customers;
 if(name==='invoice_financial_position')data=window.__financial;
 if(name==='invoice_refund_options')data={financial:window.__financial,sources:[],stock:[],benefits:[],lines:[],review_required:false};
 if(name==='invoice_benefit_review_options')data={lines:[]};
 if(name==='invoice_stock_component_evidence')data=[
   {invoice_item_id:'line',line_kind:'promotion',description:'Phone Width Bundle',
    evidence_status:'needs_confirmation',evidence_source:"Recorded choices, plus this promotion's CURRENT fixed contents",
    proposed:[{kind:'product',item_id:'socks',quantity:1,component_source:'fixed'}],
    missing:'The fixed contents of this promotion as it stood on the sale date are not recorded.'}];
 if(name==='rebuild_invoice_stock_components'){window.__rebuilt=args;data={success:true,component_rows:1};}
 if(name==='correct_invoice' && window.__failCorrection){
   const q=new Proxy({}, {get(_,key){if(key==='then')return (ok,bad)=>Promise.resolve({data:null,error:{message:'Historical component snapshots need review before changing stock or selections; metadata can still be corrected'}}).then(ok,bad);return()=>q;}});
   return q;
 }
 if(name==='create_invoice_with_details'){
   window.__tables.invoices=[...window.__tables.invoices,{...window.__tables.invoices[0],id:'created',invoice_no:'INV-NEW',status:'unpaid',paid_amount:0}];
   data='created';
 }
 if(name==='record_invoice_payment_with_instalment'){
   const taken=(args.p_payments||[]).reduce((s,p)=>s+Number(p.amount||0),0);
   const held=Number(window.__financial.net_received||0)+taken;
   const left=Math.max(Number(window.__financial.total||0)-held,0);
   const settled=left<=0.001;
   window.__financial={...window.__financial,net_received:held,outstanding:left,
     status:settled?'paid':'partially_paid'};
   window.__tables.invoices=window.__tables.invoices.map(i=>i.id===args.p_invoice_id
     ?{...i,status:settled?'paid':'partially_paid',paid_amount:held}:i);
   data={success:true};
 }
 const q=new Proxy({}, {get(_,key){if(key==='then')return (ok,bad)=>Promise.resolve({data,error:null}).then(ok,bad);return()=>q;}});return q;
 }};`;

const result = await build({
  stdin: { contents: `import React from 'react';import {createRoot} from 'react-dom/client';import {BrowserRouter} from 'react-router-dom';import InvoicesPage from './src/pages/InvoicesPage';createRoot(document.getElementById('root')).render(<BrowserRouter><InvoicesPage/></BrowserRouter>);`, resolveDir: process.cwd(), loader: 'tsx' },
  bundle: true, define: { 'import.meta.env': '{}' }, format: 'iife', write: false,
  plugins: [{ name: 'isolated-fixtures', setup(b) {
    b.onResolve({ filter: /(?:^|\/)supabase$/ }, () => ({ path: 'db', namespace: 'fixture' }));
    b.onResolve({ filter: /\/context\/AuthContext$/ }, () => ({ path: 'auth', namespace: 'fixture' }));
    b.onResolve({ filter: /\.css$/ }, () => ({ path: 'css', namespace: 'fixture' }));
    b.onLoad({ filter: /.*/, namespace: 'fixture' }, a => ({ contents: a.path === 'db' ? mock : a.path === 'auth' ? `export const useAuth=()=>({profile:{id:'owner',full_name:'Test Owner',role:'owner'},assignments:[],loading:false});` : '', loader: 'js' }));
  } }],
});
const bundle = result.outputFiles[0].text;
const css = await readFile('src/styles/globals.css', 'utf8') + '\n' + await readFile('src/components/invoices/invoice-controls.css', 'utf8');

const browser = await chromium.launch({ headless: true, executablePath: process.env.CHROME_EXECUTABLE || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' });
let checks = 0;
const ok = (label, condition, detail = '') => {
  assert.ok(condition, `${label}${detail ? ` — ${detail}` : ''}`);
  checks++; console.log(`  ok  ${label}`);
};

const mount = async (page, scenario) => {
  const s = scenarios[scenario];
  // Everything except the fixture page is refused, so nothing can reach out.
  await page.route('**/*', route => route.request().url() === 'https://invoice.test/'
    ? route.fulfill({ contentType: 'text/html', body: '<html><head><meta name="viewport" content="width=device-width,initial-scale=1"></head><body><div id="root"></div></body></html>' })
    : route.abort());
  await page.goto('https://invoice.test/');
  await page.evaluate(([t, f]) => { window.__tables = JSON.parse(JSON.stringify(t)); window.__financial = f; window.__calls = []; }, [s.tables, s.financial]);
  await page.addStyleTag({ content: css.replace(/^@import.*$/gm, '') });
  await page.addScriptTag({ content: bundle });
  await page.getByRole('button', { name: 'View', exact: true }).first().click();
};

try {
  for (const width of [375, 320]) {
    const page = await browser.newPage({ viewport: { width, height: 900 }, isMobile: true, hasTouch: true });
    page.setDefaultTimeout(8000);
    const errors = []; page.on('pageerror', e => errors.push(e.message));
    console.log(`Width ${width}`);

    // --- an ordinary unpaid invoice ------------------------------------
    await mount(page, 'unpaid');
    ok('an unpaid invoice offers Edit Invoice',
       await page.getByRole('button', { name: 'Edit Invoice', exact: true }).count() === 1);
    ok('and offers no Correct Invoice anywhere alongside it',
       await page.getByRole('button', { name: 'Correct Invoice', exact: true }).count() === 0);
    ok('Refund / Cancel is in the footer',
       await page.getByRole('button', { name: 'Refund / Cancel', exact: true }).count() === 1);
    ok('the removed standalone refund action is gone',
       await page.getByRole('button', { name: 'Record full / partial refund', exact: true }).count() === 0);
    ok('and so is the removed standalone cancel action',
       await page.getByRole('button', { name: 'Cancel invoice', exact: true }).count() === 0);

    // Payment entry starts blank, with the real outstanding amount.
    ok('the payment method starts with no selection',
       await page.getByRole('button', { name: 'Payment method', exact: true }).first().textContent()
         .then(t => t.includes('Select payment method')));
    ok('and the amount is prefilled from the outstanding balance',
       await page.getByPlaceholder('Amount').first().inputValue() === '100');
    await page.getByRole('button', { name: 'Split Payment', exact: true }).click();
    const blanks = await page.getByRole('button', { name: 'Payment method', exact: true }).count();
    const texts = await page.getByRole('button', { name: 'Payment method', exact: true }).allTextContents();
    ok('a new split row also starts blank', blanks === 2 && texts.every(t => t.includes('Select payment method')),
       texts.join(' | '));

    // A positive amount with no method must not be quietly dropped.
    await page.getByPlaceholder('Amount').nth(1).fill('25');
    const recordBtn = page.getByRole('button', { name: 'Record Payment', exact: true });
    ok('Record Payment is refused while a row has an amount but no method',
       await recordBtn.isDisabled());
    ok('and the reason is stated, not just greyed out',
       (await page.getByText('Choose a payment method for every amount entered.').count()) > 0);
    ok('nothing was sent to the server', await page.evaluate(() =>
       window.__calls.filter(c => c.name.startsWith('record_invoice_payment')).length) === 0);

    // The instalment arrangement lives here now, and expands to the agreed
    // options: in-house, provider-funded, a searchable method and 3/6/9/12 or
    // any positive whole number of months.
    ok('the payment arrangement appears in the payment section',
       await page.getByRole('group', { name: 'Payment arrangement' }).count() === 1);
    await page.getByRole('checkbox', { name: 'Instalments' }).check();
    const arrangement = page.getByRole('group', { name: 'Payment arrangement' });
    const categories = await arrangement.locator('select').first().locator('option').allTextContents();
    ok('both instalment kinds are offered',
       categories.some(t => /In-house/i.test(t)) && categories.some(t => /Provider-funded/i.test(t)), categories.join(', '));
    ok('the instalment method is searchable',
       await arrangement.getByRole('button', { name: 'Instalment payment method', exact: true }).count() === 1);
    for (const n of [3, 6, 9, 12]) {
      ok(`a ${n}-month term is offered`, await arrangement.getByRole('button', { name: `${n} months`, exact: true }).count() === 1);
    }
    await arrangement.getByRole('spinbutton', { name: 'Duration (months)' }).fill('7');
    ok('and a custom whole number of months is accepted',
       await arrangement.getByRole('spinbutton', { name: 'Duration (months)' }).inputValue() === '7');
    ok('choosing an arrangement records no payment',
       await page.evaluate(() => window.__calls.filter(c => c.name.startsWith('record_invoice_payment')).length) === 0);
    await page.getByRole('checkbox', { name: 'Instalments' }).uncheck();

    // --- the chooser ----------------------------------------------------
    await page.getByRole('button', { name: 'Refund / Cancel', exact: true }).click();
    const dialog = page.getByRole('dialog', { name: 'Refund or cancel this invoice' });
    ok('the chooser opens as a labelled dialog', await dialog.count() === 1);
    ok('it offers cancellation explicitly',
       await dialog.getByRole('button', { name: /Cancel invoice/ }).count() === 1);
    ok('and a refund explicitly',
       await dialog.getByRole('button', { name: /Full or partial refund/ }).count() === 1);
    ok('refund is unavailable when no payment is held, and says why',
       await dialog.getByRole('button', { name: /Full or partial refund/ }).isDisabled()
       && (await dialog.getByText('No refundable payment.').count()) > 0);
    ok('opening the chooser changed nothing on the server',
       await page.evaluate(() => window.__calls.filter(c =>
         ['refund_invoice_recorded', 'cancel_invoice_recorded', 'correct_invoice'].includes(c.name)).length) === 0);
    await page.keyboard.press('Escape');
    ok('Escape closes it and leaves the invoice open',
       await page.getByRole('dialog', { name: 'Refund or cancel this invoice' }).count() === 0
       && await page.getByRole('button', { name: 'Refund / Cancel', exact: true }).count() === 1);

    // --- recording a part payment keeps the invoice open -----------------
    await mount(page, 'unpaid');
    await page.getByRole('button', { name: 'Payment method', exact: true }).first().click();
    await page.getByRole('combobox', { name: 'Search payment method' }).fill('cash');
    await page.getByRole('combobox', { name: 'Search payment method' }).press('Enter');
    await page.getByPlaceholder('Amount').first().fill('40');
    ok('Record Payment becomes available once a row is complete',
       !(await page.getByRole('button', { name: 'Record Payment', exact: true }).isDisabled()));
    await page.getByRole('button', { name: 'Record Payment', exact: true }).click();
    await page.getByText('Remaining balance', { exact: false }).first().waitFor();
    ok('the invoice stays open after a part payment',
       await page.getByRole('heading', { name: /Invoice INV-TEST/ }).count() > 0
       || await page.getByText('INV-TEST', { exact: false }).count() > 0);
    ok('and shows the refreshed remaining balance',
       await page.evaluate(() => document.body.textContent.includes('S$60.00')));
    ok('the method selection is cleared for the next payment',
       await page.getByRole('button', { name: 'Payment method', exact: true }).first().textContent()
         .then(t => t.includes('Select payment method')));
    ok('and the next amount is prefilled from the new outstanding balance',
       await page.getByPlaceholder('Amount').first().inputValue() === '60');
    const payCalls = await page.evaluate(() =>
      window.__calls.filter(c => c.name === 'record_invoice_payment_with_instalment'));
    ok('exactly one payment was sent', payCalls.length === 1, `${payCalls.length} call(s)`);
    const firstRequestId = payCalls[0].args.p_request_id;
    await page.getByRole('button', { name: 'Payment method', exact: true }).first().click();
    await page.getByRole('combobox', { name: 'Search payment method' }).fill('cash');
    await page.getByRole('combobox', { name: 'Search payment method' }).press('Enter');
    await page.getByRole('button', { name: 'Record Payment', exact: true }).click();
    await page.waitForFunction(() =>
      window.__calls.filter(c => c.name === 'record_invoice_payment_with_instalment').length === 2);
    const secondRequestId = await page.evaluate(() =>
      window.__calls.filter(c => c.name === 'record_invoice_payment_with_instalment').at(-1).args.p_request_id);
    ok('a second payment carries a new request id, so it is not merged with the first',
       Boolean(firstRequestId) && Boolean(secondRequestId) && firstRequestId !== secondRequestId,
       `${firstRequestId} vs ${secondRequestId}`);

    // --- settling in full shows the paid invoice --------------------------
    await mount(page, 'unpaid');
    await page.getByRole('button', { name: 'Payment method', exact: true }).first().click();
    await page.getByRole('combobox', { name: 'Search payment method' }).fill('cash');
    await page.getByRole('combobox', { name: 'Search payment method' }).press('Enter');
    await page.getByRole('button', { name: 'Record Payment', exact: true }).click();
    await page.getByRole('button', { name: 'Correct Invoice', exact: true }).waitFor();
    ok('paying in full leaves the invoice open on its paid detail',
       await page.getByRole('button', { name: 'Correct Invoice', exact: true }).count() === 1
       && await page.getByRole('button', { name: 'Edit Invoice', exact: true }).count() === 0);
    ok('and it is not still asking for a payment',
       await page.getByRole('button', { name: 'Record Payment', exact: true }).count() === 0);

    // --- a mutation that succeeds and a refresh that fails ---------------
    await mount(page, 'unpaid');
    // The payment succeeds; reloading the invoice afterwards does not.
    await page.evaluate(() => { window.__failInvoiceReload = true; });
    await page.getByRole('button', { name: 'Payment method', exact: true }).first().click();
    await page.getByRole('combobox', { name: 'Search payment method' }).fill('cash');
    await page.getByRole('combobox', { name: 'Search payment method' }).press('Enter');
    await page.getByPlaceholder('Amount').first().fill('40');
    await page.getByRole('button', { name: 'Record Payment', exact: true }).click();
    const afterCalls = await page.evaluate(() =>
      window.__calls.filter(c => c.name === 'record_invoice_payment_with_instalment').length);
    ok('a recorded payment is never sent twice by the interface', afterCalls === 1, `${afterCalls} call(s)`);
    ok('a failed refresh is reported as a display problem, not a failed payment',
       await page.getByText('The payment was recorded', { exact: false }).count() > 0);
    ok('and the operator is told not to pay again',
       await page.getByText('Do not record the payment again', { exact: false }).count() > 0);
    await page.evaluate(() => { window.__failInvoiceReload = false; });

    // --- a paid invoice --------------------------------------------------
    await mount(page, 'paid');
    ok('a paid invoice offers Correct Invoice exactly once',
       await page.getByRole('button', { name: 'Correct Invoice', exact: true }).count() === 1);
    ok('and no ordinary Edit Invoice',
       await page.getByRole('button', { name: 'Edit Invoice', exact: true }).count() === 0);
    await page.getByRole('button', { name: 'Refund / Cancel', exact: true }).click();
    ok('refund is offered when a payment is actually held',
       !(await page.getByRole('dialog').getByRole('button', { name: /Full or partial refund/ }).isDisabled()));
    await page.keyboard.press('Escape');

    // Payment correction sits with the payment history.
    ok('payment correction is offered beside the recorded payment',
       await page.getByRole('button', { name: 'Correct amount / date', exact: true }).count() === 1);

    // The audited notice must come before the business date.
    await page.getByRole('button', { name: 'Correct Invoice', exact: true }).click();
    const order = await page.evaluate(() => {
      const notice = Array.from(document.querySelectorAll('.alert')).find(e => e.textContent.includes('Audited invoice correction'));
      const dateField = Array.from(document.querySelectorAll('label')).find(e => e.textContent.includes('Invoice business date'));
      if (!notice || !dateField) return null;
      return (notice.compareDocumentPosition(dateField) & Node.DOCUMENT_POSITION_FOLLOWING) !== 0;
    });
    ok('the audited correction notice precedes the invoice business date', order === true);

    // A saved arrangement loads into the correction form and survives a
    // correction that has nothing to do with it.
    const arrangementOnCorrection = page.getByRole('group', { name: 'Payment arrangement' });
    ok('the saved arrangement is shown on a correction',
       await arrangementOnCorrection.count() === 1
       && await arrangementOnCorrection.getByRole('checkbox', { name: 'Instalments' }).isChecked());
    ok('with its saved term',
       await arrangementOnCorrection.getByRole('spinbutton', { name: 'Duration (months)' }).inputValue() === '6');
    await page.getByPlaceholder('e.g. Wrong quantity keyed at the till').fill('Fix a note, nothing else');
    await page.getByRole('button', { name: 'Save Changes', exact: true }).click();
    const correction = await page.evaluate(() => window.__calls.findLast(c => c.name === 'correct_invoice'));
    ok('an unrelated correction preserves the saved instalment settings',
       correction?.args?.p_header?.instalment_category === 'in_house'
       && correction?.args?.p_header?.instalment_method_id === 'bank'
       && Number(correction?.args?.p_header?.instalment_months) === 6,
       JSON.stringify(correction?.args?.p_header ?? {}).slice(0, 120));

    // --- a refused store change offers the review, where the error is -----
    await mount(page, 'paid');
    await page.evaluate(() => { window.__failCorrection = true; });
    await page.getByRole('button', { name: 'Correct Invoice', exact: true }).click();
    await page.getByPlaceholder('e.g. Wrong quantity keyed at the till').fill('Move this invoice to the other store');
    await page.getByRole('button', { name: 'Save Changes', exact: true }).click();
    const review = page.getByRole('group', { name: 'Historical stock evidence review' });
    await review.waitFor();
    ok('a refused store change opens the evidence review', await review.count() === 1);
    // The bug this catches: the review rendered a hundred lines above the error,
    // so nobody scrolled up to find it.
    const gap = await page.evaluate(() => {
      const err = Array.from(document.querySelectorAll('.alert-danger'))
        .find(e => e.textContent.includes('Historical component snapshots need review'));
      const panel = document.querySelector('.invoice-evidence-review');
      if (!err || !panel) return null;
      return Math.abs(panel.getBoundingClientRect().top - err.getBoundingClientRect().bottom);
    });
    ok('and it sits with the error rather than elsewhere in the form',
       gap !== null && gap < 120, `${gap}px away`);
    ok('the evidence names the line and where it came from',
       await review.getByText('Phone Width Bundle', { exact: false }).count() > 0
       && await review.getByText('CURRENT fixed contents', { exact: false }).count() > 0);
    ok('a line needing confirmation blocks the rebuild until it is confirmed',
       await review.getByRole('button', { name: /Record this evidence/ }).isDisabled());
    await review.getByRole('checkbox').first().check();
    await review.getByRole('textbox').first().fill('Checked against the original till record');
    ok('once confirmed with a reason it can be recorded',
       !(await review.getByRole('button', { name: /Record this evidence/ }).isDisabled()));
    await review.getByRole('button', { name: /Record this evidence/ }).click();
    const rebuilt = await page.evaluate(() => window.__rebuilt);
    ok('the confirmation and reason reach the server',
       rebuilt?.p_reason === 'Checked against the original till record'
       && Array.isArray(rebuilt?.p_confirmations) && rebuilt.p_confirmations.length === 1,
       JSON.stringify(rebuilt ?? {}).slice(0, 120));
    ok('and the operator is told to save again rather than left guessing',
       await page.getByText('Press Save Changes again', { exact: false }).count() > 0);
    await page.evaluate(() => { window.__failCorrection = false; });
    await page.getByRole('button', { name: 'Cancel', exact: true }).click();

    // --- a refunded invoice must not look ordinary ------------------------
    await mount(page, 'refunded');
    ok('a refunded invoice does not fall into the ordinary unpaid-edit path',
       await page.getByRole('button', { name: 'Edit Invoice', exact: true }).count() === 0);
    ok('it still offers audited correction',
       await page.getByRole('button', { name: 'Correct Invoice', exact: true }).count() === 1);

    // --- creation continues into the new invoice --------------------------
    await mount(page, 'unpaid');
    await page.getByRole('button', { name: 'Close', exact: true }).first().click();
    await page.getByRole('button', { name: 'New Invoice', exact: true }).click();
    const noticeInNew = await page.getByText('Audited invoice correction', { exact: false }).count();
    ok('a new invoice carries no audited-correction notice', noticeInNew === 0);
    ok('and instalment options are not at the top of the creation form',
       await page.getByText('Payment arrangement', { exact: false }).count() === 0);

    ok('no unexpected browser errors', errors.length === 0, errors.join(' | '));
    await page.close();
  }
  console.log(`\n${checks} checks passed.`);
} finally {
  await browser.close();
}
