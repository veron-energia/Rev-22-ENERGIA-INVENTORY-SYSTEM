// Selecting text in a popup and letting go outside it must not close the popup
// (screen recording of 7 Nov 2026: New Invoice asked to discard, and the
// survey's Edit details closed with what was typed).
//
// Only a real browser shows this. A browser sends the click of a press and a
// release on different elements to the nearest element holding both, here the
// backdrop, so a popup that closes on a click on its backdrop took the end of a
// drag for a click outside. jsdom sends no such click by itself, so these are
// real mouse drags in Chrome, on the real popups with the app's real stylesheets.
// The supabase client and the signed-in user are stubbed; every network request
// is blocked. Every name and phone is made up, the phone in the ACMA's fictional
// range.
//
// Usage: node scripts/ui/tests/popup-drag-outside-browser.mjs
import { build } from 'esbuild';
import { createRequire } from 'node:module';
import { readFile } from 'node:fs/promises';
const require = createRequire(import.meta.url);
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || '/Users/shinthantaungstanley/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');

const built = await build({
  stdin: {
    contents: `
      import React from 'react';
      import { createRoot } from 'react-dom/client';
      import { Modal } from './src/components/ui';
      import SurveyDetailModal from './src/components/SurveyDetailModal';
      import { QuickCustomerModal } from './src/components/customers/QuickCustomerModal';
      import { PaymentQrPopup } from './src/components/invoices/PaymentQrPopup';
      import { InvoiceGuidedAction } from './src/components/invoices/InvoiceGuidedAction';
      import { CreditSpendingRules } from './src/components/therapy/CreditSpendingRules';
      import { BenefitChoicePanel } from './src/components/therapy/BenefitChoicePanel';
      import { VoucherClaimPanel } from './src/components/therapy/VoucherClaimPanel';
      import ProductsPage from './src/pages/ProductsPage';

      const TEXT = 'A long made-up sentence that fills the box from one side to the other and goes on well past its end, so a drag has plenty to select.';
      const field = <div className="form-group"><label>Note</label><input defaultValue={TEXT} /></div>;
      const pixel = 'data:image/gif;base64,R0lGODlhAQABAAAAACH5BAEKAAEALAAAAAABAAEAAAICTAEAOw==';

      // As Confirm Exchange opens over the exchange being entered.
      function Nested({ close }) {
        const [upper, setUpper] = React.useState(true);
        return <Modal title="Below" confirmClose onClose={close}>
          <p id="below">The form below</p>
          {upper && <Modal title="On top" onClose={() => { window.__upperClosed++; setUpper(false); }}>{field}</Modal>}
        </Modal>;
      }

      const popups = {
        plain: close => <Modal title="A window with no form" onClose={close}>{field}</Modal>,
        form: close => <Modal title="A window with a form" confirmClose onClose={close}>{field}</Modal>,
        // New Invoice's own settings: it leaves the sidebar visible and usable.
        invoice: close => <Modal title="New Invoice" wide confirmClose onClose={close}>{field}</Modal>,
        survey: close => <SurveyDetailModal surveyId="survey-1" onClose={close} onSaved={() => {}} />,
        quick: close => <QuickCustomerModal initialName={TEXT} onCreated={() => {}} onPickedExisting={() => {}} onClose={close} />,
        qr: close => <PaymentQrPopup qr={{ label: 'PayNow', methodName: 'PayNow' }} image={{ url: pixel }} amount={10} reference="INV-TEST" onClose={close} />,
        guided: close => <InvoiceGuidedAction invoiceId="invoice-1" canApprove onDone={() => {}} onClose={close} />,
        rules: close => <CreditSpendingRules packageId="package-1" packageName="Made-up package" canEdit onClose={close} />,
        benefit: close => <BenefitChoicePanel purchasedId="unit-1" canSwitch onClose={close} />,
        voucher: close => <VoucherClaimPanel entitlementId="entitlement-1" canClaim onClose={close} />,
        nested: close => <Nested close={close} />,
        products: () => <ProductsPage />,
      };

      function App({ mode }) {
        const [open, setOpen] = React.useState(true);
        const close = () => { window.__closed++; setOpen(false); };
        return <div style={{ display: 'flex', minHeight: '100vh' }}>
          <aside id="sidebar" style={{ width: 240, flexShrink: 0 }}>The sidebar</aside>
          <main style={{ flex: 1 }}>{open && popups[mode](close)}</main>
        </div>;
      }
      window.__closed = 0;
      window.__upperClosed = 0;
      createRoot(document.getElementById('root')).render(
        <React.StrictMode><App mode={new URLSearchParams(location.search).get('m')} /></React.StrictMode>);`,
    resolveDir: process.cwd(), loader: 'tsx',
  },
  bundle: true, write: false, format: 'iife', jsx: 'automatic',
  define: { 'process.env.NODE_ENV': '"development"', 'import.meta.env': '{"DEV":false,"VITE_SUPABASE_URL":"x","VITE_SUPABASE_ANON_KEY":"x"}' },
  plugins: [{ name: 'stub', setup(b) {
    b.onResolve({ filter: /(^|\/)supabase$/ }, () => ({ path: 'db', namespace: 'st' }));
    b.onResolve({ filter: /\/context\/AuthContext$/ }, () => ({ path: 'auth', namespace: 'st' }));
    b.onResolve({ filter: /\.css$/ }, () => ({ path: 'css', namespace: 'st' }));
    b.onLoad({ filter: /.*/, namespace: 'st' }, a => ({ loader: 'js', contents: a.path === 'db' ? `
        const answers = {
          health_survey_detail: { symptoms: [], survey: { id: 'survey-1', survey_no: 'HS-TEST-0001', full_name: 'Made Up',
            first_name: 'Made', last_name: 'Up', phone: '+61491570110', email: 'made.up@example.com',
            date_of_birth: '1980-01-02', sex: 'Female', occupation: 'Retired', customer_id: null,
            others_text: 'A long made-up list of symptoms that fills the box from one side to the other and goes on well past its end, so a drag has plenty to select.' } },
          consultant_notes_for: [],
        };
        const query = { select: () => query, eq: () => query, is: () => query, in: () => query, order: () => query, limit: () => query,
          maybeSingle: async () => ({ data: null, error: null }), single: async () => ({ data: null, error: null }),
          then: res => res({ data: [], error: null }) };
        export const supabase = {
          rpc: async name => name in answers ? { data: answers[name], error: null } : { data: null, error: { message: 'Not answered in this test' } },
          from: () => query,
        };`
      : a.path === 'auth' ? "export const useAuth = () => ({ profile: { id: 'owner-1', role: 'owner' } });" : '' }));
  } }],
});
// In the app's order: globals first (main.tsx), then the components' own.
const css = (await Promise.all(['src/styles/globals.css', 'src/components/invoices/invoice-controls.css',
  'src/components/customers/quick-customer.css', 'src/components/therapy/therapy.css']
  .map(f => readFile(f, 'utf8')))).join('\n').replace(/^@import.*$/gm, '');

const browser = await chromium.launch({ headless: true,
  executablePath: process.env.CHROME_EXECUTABLE || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' });
let failures = 0;
const check = (name, ok, detail) => {
  if (ok) console.log(`  ok   ${name}`);
  else { failures++; console.log(`  FAIL ${name}${detail === undefined ? '' : ' — ' + detail}`); }
};

const DISCARD = 'Discard what you have entered? It will not be saved.';

/** Opens one popup. page.answer is how the next "discard?" question is answered. */
async function open(mode, options = { viewport: { width: 1280, height: 800 } }) {
  const context = await browser.newContext(options);
  const page = await context.newPage();
  await page.route('**/*', r => r.request().url().startsWith('https://tests.invalid/')
    ? r.fulfill({ contentType: 'text/html', body: '<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"></head><body><div id="root"></div></body></html>' })
    : r.abort());
  page.asked = [];
  page.answer = false;
  page.on('dialog', d => { page.asked.push(d.message()); return page.answer ? d.accept() : d.dismiss(); });
  await page.goto('https://tests.invalid/?m=' + mode);
  await page.addStyleTag({ content: css });
  await page.addScriptTag({ content: built.outputFiles[0].text });
  await page.waitForTimeout(150);
  return page;
}

/** A point on the backdrop just outside the popup; the one the drag ends on. */
const onBackdrop = (page, { backdrop, panel }) => page.evaluate(({ backdrop, panel }) => {
  const p = [...document.querySelectorAll(panel)].pop().getBoundingClientRect();
  const b = [...document.querySelectorAll(backdrop)].pop();
  const mid = { x: p.left + p.width / 2, y: p.top + p.height / 2 };
  const spots = [[p.left - 6, mid.y], [p.right + 6, mid.y], [mid.x, p.top - 6], [mid.x, p.bottom + 6]];
  const hit = spots.find(([x, y]) => document.elementFromPoint(x, y) === b);
  return hit ? { x: hit[0], y: hit[1] } : null;
}, { backdrop, panel });

// On whole pixels. A press on a half pixel right on the edge between two letters
// leaves Chrome's selection collapsed for the whole drag, in a bare input with no
// app code too, which has nothing to do with popups.
const centre = async locator => {
  await locator.scrollIntoViewIfNeeded();
  const b = await locator.boundingBox();
  return { x: Math.round(b.x + b.width / 2), y: Math.round(b.y + b.height / 2) };
};

const drag = async (page, from, to) => {
  await page.mouse.move(from.x, from.y);
  await page.mouse.down();
  await page.mouse.move(to.x, to.y, { steps: 12 });
  await page.mouse.up();
  await page.waitForTimeout(40);
};

const selectedIn = locator => locator.evaluate(e => e.selectionEnd - e.selectionStart);
const closes = page => page.evaluate(() => window.__closed);

const OTHERS = '.form-group:has(> label:text-is("Others (symptoms)")) input';

const POPUPS = [
  { name: 'a window with no form', mode: 'plain', backdrop: '.modal-overlay', panel: '.modal', press: 'input', typed: true },
  { name: 'a window with a form', mode: 'form', backdrop: '.modal-overlay', panel: '.modal', press: 'input', typed: true, asks: true },
  { name: 'New Invoice', mode: 'invoice', backdrop: '.modal-overlay', panel: '.modal', press: 'input', typed: true, asks: true },
  { name: "the survey's Edit details", mode: 'survey', backdrop: '.modal-overlay', panel: '.modal', typed: true,
    press: OTHERS, prepare: page => page.locator('[data-edit-details]').click() },
  { name: 'Add a customer', mode: 'quick', backdrop: '.quick-customer-backdrop', panel: '.quick-customer', press: 'input', typed: true },
  { name: 'the payment QR', mode: 'qr', backdrop: '.invoice-qr-backdrop', panel: '.invoice-qr', press: 'h3' },
  { name: 'Refund or cancel', mode: 'guided', backdrop: '.invoice-guided-backdrop', panel: '.invoice-guided', press: 'h3' },
  { name: 'Credit spending rules', mode: 'rules', backdrop: '.credit-rules-backdrop', panel: '.credit-rules', press: 'h3' },
  { name: 'the benefit choice', mode: 'benefit', backdrop: '.credit-rules-backdrop', panel: '.credit-rules', press: 'h3' },
  { name: 'Claim vouchers', mode: 'voucher', backdrop: '.credit-rules-backdrop', panel: '.credit-rules', press: 'h3' },
];

for (const popup of POPUPS) {
  console.log(popup.name);
  const page = await open(popup.mode);
  const shown = () => page.locator(popup.panel).count();
  check('it opens', await shown() === 1, await page.evaluate(() => document.body.textContent.slice(0, 200)));
  await popup.prepare?.(page);
  const press = page.locator(`${popup.panel} ${popup.press}`).first();
  if (popup.prepare) await press.waitFor();
  if (popup.typed) check('its box holds text to select', (await press.inputValue()).length > 40, await press.inputValue());
  const start = await centre(press);
  const outside = await onBackdrop(page, popup);
  check('there is backdrop beside it to let go on', !!outside);

  await drag(page, start, outside);
  check('a drag from inside to the backdrop leaves it open', await shown() === 1 && await closes(page) === 0, `closed ${await closes(page)}`);
  check('and asks nothing', page.asked.length === 0, page.asked.join(' | '));
  page.asked.length = 0;
  if (await shown() === 0) { await page.context().close(); continue; }
  if (popup.typed) check('and the text stays selected', await selectedIn(press) > 0, await selectedIn(press));

  await drag(page, outside, start);
  check('a drag from the backdrop into it leaves it open', await shown() === 1 && await closes(page) === 0, `closed ${await closes(page)}`);
  check('and asks nothing', page.asked.length === 0, page.asked.join(' | '));
  page.asked.length = 0;
  if (await shown() === 0) { await page.context().close(); continue; }

  // The test of the fix being too strong: a real click outside still works,
  // straight after each of those drags.
  await drag(page, start, outside);
  page.asked.length = 0;
  if (popup.asks) {
    await page.mouse.click(outside.x, outside.y);
    await page.waitForTimeout(40);
    check('a click on the backdrop still asks before discarding', page.asked.join() === DISCARD && await shown() === 1, page.asked.join(' | '));
    page.answer = true;
  }
  await page.mouse.click(outside.x, outside.y);
  await page.waitForTimeout(40);
  check('a click on the backdrop still closes it', await shown() === 0 && await closes(page) === 1, `closed ${await closes(page)}`);
  await page.context().close();
}

// The recording: from the start of Others (symptoms), straight out past the
// popup's right edge, the text scrolling along.
console.log('the drag in the recording');
{
  const page = await open('survey');
  await page.locator('[data-edit-details]').click();
  const box = page.locator(`.modal ${OTHERS}`).first();
  await box.waitFor();
  const b = await box.boundingBox();
  const panel = await page.locator('.modal').boundingBox();
  const y = Math.round(b.y + b.height / 2);
  await drag(page, { x: Math.round(b.x) + 8, y }, { x: Math.round(panel.x + panel.width) + 30, y });
  check('Edit details stays open', await page.locator('.modal').count() === 1 && await closes(page) === 0, `closed ${await closes(page)}`);
  check('with the text selected', await selectedIn(box) > 0, await selectedIn(box));
  await page.context().close();
}

// The two forms that ask only once something would be lost: a drag never asks,
// even then, and a real click does.
console.log('the discard question');
{
  const POP = { backdrop: '.modal-overlay', panel: '.modal' };
  const page = await open('survey');
  await page.locator('[data-edit-details]').click();
  const box = page.locator(`.modal ${OTHERS}`).first();
  await box.waitFor();
  const spot = await onBackdrop(page, POP);
  const typed = 'Made-up symptoms typed for this test, long enough for a drag to select some of them';
  await box.fill(typed);
  await drag(page, await centre(box), spot);
  check('Edit details, changed: a drag out asks nothing and leaves it open', page.asked.length === 0 && await page.locator('.modal').count() === 1, page.asked.join(' | '));
  await page.mouse.click(spot.x, spot.y);
  await page.waitForTimeout(40);
  check('a click on the backdrop asks', page.asked.join() === DISCARD, page.asked.join(' | '));
  check('and No keeps what was typed', await box.inputValue() === typed && await closes(page) === 0, await box.inputValue());
  await page.locator('.modal-footer button', { hasText: /^Close$/ }).click();
  await page.waitForTimeout(40);
  check('the Close button asks too', page.asked.length === 2 && await page.locator('.modal').count() === 1, page.asked.join(' | '));
  page.answer = true;
  await page.mouse.click(spot.x, spot.y);
  await page.waitForTimeout(40);
  check('and Yes closes it', await closes(page) === 1, `closed ${await closes(page)}`);
  await page.context().close();

  const products = await open('products');
  const add = () => products.getByRole('button', { name: 'Add Product' }).click();
  await add();
  const where = await onBackdrop(products, POP);
  await products.mouse.click(where.x, where.y);
  await products.waitForTimeout(40);
  check('Add Product, untouched: a click on the backdrop closes it and asks nothing', products.asked.length === 0 && await products.locator('.modal').count() === 0, products.asked.join(' | '));
  await add();
  const name = products.locator('.modal input').first();
  await name.fill(typed);
  await drag(products, await centre(name), where);
  check('Add Product, typed in: a drag out asks nothing and leaves it open', products.asked.length === 0 && await products.locator('.modal').count() === 1, products.asked.join(' | '));
  check('with the text selected', await selectedIn(name) > 0, await selectedIn(name));
  await products.mouse.click(where.x, where.y);
  await products.waitForTimeout(40);
  check('a click on the backdrop asks, and No keeps what was typed', products.asked.join() === DISCARD && await name.inputValue() === typed, products.asked.join(' | '));
  products.asked.length = 0;
  await products.locator('.modal-footer button', { hasText: /^Cancel$/ }).click();
  await products.waitForTimeout(40);
  check('Cancel closes it and asks nothing', products.asked.length === 0 && await products.locator('.modal').count() === 0, products.asked.join(' | '));
  await products.context().close();
}

// New Invoice leaves the sidebar usable: a drag can end there too.
console.log('letting go elsewhere');
{
  const POP = { backdrop: '.modal-overlay', panel: '.modal' };
  const page = await open('invoice');
  const input = page.locator('.modal input').first();
  await drag(page, await centre(input), await centre(page.locator('#sidebar')));
  check('New Invoice: a drag ending on the sidebar leaves it open and asks nothing', await page.locator('.modal').count() === 1 && page.asked.length === 0, page.asked.join(' | '));
  const outside = await onBackdrop(page, POP);
  page.answer = true;
  await page.mouse.click(outside.x, outside.y);
  await page.waitForTimeout(40);
  check('and the next click on the backdrop asks and closes it', page.asked.join() === DISCARD && await closes(page) === 1, page.asked.join(' | '));
  await page.context().close();

  // The mouse leaves the page altogether: no click ever comes.
  const beyond = await open('plain');
  const box = beyond.locator('.modal input').first();
  await drag(beyond, await centre(box), { x: -40, y: 300 });
  check('a drag ending past the edge of the page leaves it open', await beyond.locator('.modal').count() === 1 && await closes(beyond) === 0, `closed ${await closes(beyond)}`);
  const spot = await onBackdrop(beyond, POP);
  await beyond.mouse.click(spot.x, spot.y);
  await beyond.waitForTimeout(40);
  check('and the next click on the backdrop closes it', await closes(beyond) === 1, `closed ${await closes(beyond)}`);
  await beyond.context().close();
}

// One popup over another.
console.log('a window over a form');
{
  const page = await open('nested');
  const POP = { backdrop: '.modal-overlay', panel: '.modal' };
  const top = await onBackdrop(page, POP);
  await drag(page, await centre(page.locator('.modal .modal input').first()), top);
  check('a drag from the top window to the backdrop closes neither and asks nothing',
    await page.locator('.modal').count() === 2 && page.asked.length === 0 && await closes(page) === 0, page.asked.join(' | '));
  await page.mouse.click(top.x, top.y);
  await page.waitForTimeout(40);
  check('a click on the backdrop closes only the top window', await page.evaluate(() => window.__upperClosed) === 1
    && await page.locator('.modal').count() === 1 && page.asked.length === 0 && await closes(page) === 0, page.asked.join(' | '));
  await page.context().close();
}

// A phone or tablet: a tap sends press, release and click on one spot.
console.log('a touch screen');
{
  const page = await open('plain', { viewport: { width: 390, height: 800 }, hasTouch: true, isMobile: true });
  const body = await centre(page.locator('.modal-body'));
  await page.touchscreen.tap(body.x, body.y);
  await page.waitForTimeout(40);
  check('a tap inside leaves it open', await page.locator('.modal').count() === 1);
  await page.touchscreen.tap(195, 8);
  await page.waitForTimeout(40);
  check('a tap on the backdrop closes it', await page.locator('.modal').count() === 0 && await closes(page) === 1, `closed ${await closes(page)}`);
  await page.context().close();
}

await browser.close();
console.log(failures ? `\n${failures} failed` : '\nAll passed');
process.exit(failures ? 1 : 0);
