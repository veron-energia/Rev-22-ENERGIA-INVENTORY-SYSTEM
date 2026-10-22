// Two invoice-screen fixes, measured in Chrome with the app's real stylesheets
// (owner, 22 Oct 2026).
//
// Instalments (Record Payment and the exchange's extra payment): the Duration
// row was a full-width <label>, so a click anywhere beside a custom duration
// went to its first control, the 3 button, and 24 months became 3. On Correct
// Invoice for a paid invoice the Instalments tick sat in a full-width label too,
// so a click at the far end of its row unticked it and wiped the terms.
//
// Add a customer (from an invoice, and from the Credit Package and Premium
// Bundle split rows): the country list filled the phone row and pushed the
// number box out of the window. Other screens' phone boxes must not change.
//
// The real components are mounted with the supabase client and the signed-in
// user stubbed; every network request is blocked. The phone number is in the
// ACMA's fictional range.
//
// Usage: node scripts/ui/tests/instalment-and-phone-browser.mjs
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
      import { InstalmentPortionFields, emptyPortion } from './src/components/invoices/InstalmentPortionFields';
      import { InstalmentFields } from './src/components/invoices/InstalmentFields';
      import { QuickCustomerModal } from './src/components/customers/QuickCustomerModal';
      import PhoneInput from './src/components/PhoneInput';
      const methods = [{ id: 'pm-1', name: 'PayNow' }];
      function Portion() {
        const [v, setV] = React.useState({ ...emptyPortion, method_id: 'pm-1' });
        window.__months = v.months;
        return <InstalmentPortionFields value={v} onChange={setV} methods={methods} receivedNow={100}
          onReceivedNow={() => {}} error={null} />;
      }
      function Terms() {
        const [v, setV] = React.useState({ instalment_category: 'in_house', instalment_method_id: 'pm-1', instalment_months: 24 });
        window.__terms = v;
        return <InstalmentFields value={v} onChange={setV} methods={methods} />;
      }
      function Elsewhere() {
        const [p, setP] = React.useState('');
        return <div className="form-group" id="elsewhere"><label>Phone * (up to 3 customers)</label><PhoneInput value={p} onChange={setP} /></div>;
      }
      const mode = new URLSearchParams(location.search).get('m');
      createRoot(document.getElementById('root')).render(mode === 'qc'
        ? <><Elsewhere /><QuickCustomerModal onCreated={() => {}} onPickedExisting={() => {}} onClose={() => {}} /></>
        : <div className="modal" style={{ maxWidth: 640, margin: '10px auto', padding: 16 }}><Portion /><Terms /></div>);`,
    resolveDir: process.cwd(), loader: 'tsx',
  },
  bundle: true, write: false, format: 'iife', jsx: 'automatic',
  define: { 'process.env.NODE_ENV': '"development"' },
  plugins: [{ name: 'stub', setup(b) {
    b.onResolve({ filter: /(^|\/)supabase$/ }, () => ({ path: 'db', namespace: 'st' }));
    b.onResolve({ filter: /\/context\/AuthContext$/ }, () => ({ path: 'auth', namespace: 'st' }));
    b.onResolve({ filter: /\.css$/ }, () => ({ path: 'css', namespace: 'st' }));
    b.onLoad({ filter: /.*/, namespace: 'st' }, a => ({ loader: 'js', contents: a.path === 'db'
      ? 'export const supabase = { rpc: async () => ({ data: { candidates: [], used: 0, remaining: 3 }, error: null }) };'
      : a.path === 'auth' ? "export const useAuth = () => ({ profile: { id: 'staff-1', role: 'staff' } });" : '' }));
  } }],
});
// In the app's order: globals first (main.tsx), then the components' own.
const css = (await Promise.all(['src/styles/globals.css', 'src/components/invoices/invoice-controls.css',
  'src/components/customers/quick-customer.css'].map(f => readFile(f, 'utf8')))).join('\n').replace(/^@import.*$/gm, '');

const browser = await chromium.launch({ headless: true,
  executablePath: process.env.CHROME_EXECUTABLE || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' });
let failures = 0;
const check = (name, ok, detail) => {
  if (ok) console.log(`  ok   ${name}`);
  else { failures++; console.log(`  FAIL ${name}${detail === undefined ? '' : ' — ' + detail}`); }
};
const open = async (m, width) => {
  const page = await browser.newPage({ viewport: { width, height: 900 } });
  await page.route('**/*', r => r.request().url().startsWith('https://tests.invalid/')
    ? r.fulfill({ contentType: 'text/html', body: '<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"></head><body><div id="root"></div></body></html>' })
    : r.abort());
  await page.goto('https://tests.invalid/?m=' + m);
  await page.addStyleTag({ content: css });
  await page.addScriptTag({ content: built.outputFiles[0].text });
  await page.waitForTimeout(150);
  return page;
};

// ---- instalments ------------------------------------------------------------
for (const width of [1024, 390]) {
  const page = await open('inst', width);
  const months = () => page.evaluate(() => window.__months);
  const box = page.getByRole('spinbutton', { name: 'Custom number of months' });
  const typeIn = async s => { await box.fill(''); await box.click(); await page.keyboard.type(s); };
  const clickAt = async (locator, where) => {
    const b = await locator.boundingBox();
    await page.mouse.click(where === 'end' ? b.x + b.width - 6 : b.x + 4, b.y + Math.min(8, b.height / 2));
  };
  // The element around the month buttons: the label it was, the group it is.
  const row = page.locator('.instalment-portion > :has(> .instalment-months)');

  await typeIn('24');
  await clickAt(row, 'end');
  check(`${width}px: a click on the blank end of the Duration row leaves 24`, await months() === 24 && await box.inputValue() === '24',
    `${await months()} / ${await box.inputValue()}`);
  await clickAt(row, 'start');
  check(`${width}px: a click on the word Duration leaves 24`, await months() === 24, await months());
  await clickAt(page.locator('.instalment-months .muted'), 'start');
  check(`${width}px: a click on the word months leaves 24`, await months() === 24, await months());
  await typeIn('36');
  check(`${width}px: 36 typed key by key is 36`, await months() === 36 && await box.inputValue() === '36', `${await months()} / ${await box.inputValue()}`);
  await typeIn('120');
  check(`${width}px: 120 typed key by key is 120`, await months() === 120 && await box.inputValue() === '120', `${await months()} / ${await box.inputValue()}`);
  await page.locator('.instalment-months .btn', { hasText: /^6$/ }).click();
  check(`${width}px: preset 6 chooses 6 and empties the box`, await months() === 6 && await box.inputValue() === '', `${await months()} / ${await box.inputValue()}`);

  // The row keeps the look the label gave it: the Amount label is the same rule.
  const look = await page.evaluate(() => {
    const pick = e => { const s = getComputedStyle(e); return [s.display, s.fontSize, s.fontWeight, s.color, s.marginBottom].join(' '); };
    return { row: pick(document.querySelector('.instalment-months').parentElement),
             amount: pick([...document.querySelectorAll('.instalment-portion label')].find(l => l.textContent.startsWith('Amount'))) };
  });
  check(`${width}px: the Duration row looks as the Amount label does`, look.row === look.amount, JSON.stringify(look));

  // Correct Invoice on a paid invoice.
  const tick = page.getByRole('checkbox', { name: 'Instalments' });
  const fieldset = await tick.locator('xpath=ancestor::fieldset[1]').boundingBox();
  const t = await tick.boundingBox();
  await page.mouse.click(fieldset.x + fieldset.width - 20, t.y + t.height / 2);
  const terms = await page.evaluate(() => window.__terms);
  check(`${width}px: a click at the far end of the Instalments row keeps the tick, method and 24 months`,
    await tick.isChecked() && terms.instalment_months === 24 && terms.instalment_method_id === 'pm-1', JSON.stringify(terms));
  await tick.click();
  check(`${width}px: the tick itself still unticks`, !(await tick.isChecked()));
  await page.close();
}

// ---- Add a customer's phone -------------------------------------------------
for (const width of [1280, 768, 560, 430, 390, 375, 360, 320]) {
  const page = await open('qc', width);
  const m = await page.evaluate(() => {
    const r = e => { const b = e.getBoundingClientRect(); return { l: Math.round(b.left), r: Math.round(b.right), w: Math.round(b.width) }; };
    const dlg = document.querySelector('.quick-customer'), pi = dlg.querySelector('.phone-input');
    const other = document.querySelector('#elsewhere .phone-input');
    return { dialog: r(dlg), row: r(pi), select: r(pi.querySelector('select')), input: r(pi.querySelector('input')),
             dir: getComputedStyle(pi).flexDirection,
             fonts: [getComputedStyle(pi.querySelector('select')).fontSize, getComputedStyle(pi.querySelector('input')).fontSize].join(' '),
             fits: (() => {   // the chosen country's words against the room the list leaves them
               const sel = pi.querySelector('select'), s = getComputedStyle(sel);
               const ctx = document.createElement('canvas').getContext('2d'); ctx.font = s.font;
               return Math.ceil(ctx.measureText(sel.selectedOptions[0].textContent).width) + 18
                 <= sel.clientWidth - parseFloat(s.paddingLeft) - parseFloat(s.paddingRight);
             })(),
             other: { select: r(other.querySelector('select')).w, dir: getComputedStyle(other).flexDirection } };
  });
  const d = JSON.stringify(m);
  check(`${width}px: the number box lies inside the window`, m.input.l >= m.dialog.l && m.input.r <= m.dialog.r, d);
  if (width > 380) {
    check(`${width}px: country list and number box side by side, the box usable`,
      m.dir === 'row' && m.select.w === 170 && m.input.w >= 120 && m.input.r === m.row.r, d);
    check(`${width}px: another screen's phone box keeps the component's 132px country list`,
      m.other.dir === 'row' && m.other.select === 132, d);
  } else {
    check(`${width}px: stacked, each the full row`, m.dir === 'column' && m.select.w === m.row.w && m.input.w === m.row.w, d);
  }
  check(`${width}px: 16px type, so iPhones do not zoom; "Singapore (+65)" fits`, m.fonts === '16px 16px' && m.fits, d);

  if (width === 1280 || width === 375) {
    const dialog = page.locator('.quick-customer[role="dialog"]');
    const byLabel = dialog.getByLabel('Phone');
    check(`${width}px: "Phone *" names the number box`,
      await byLabel.count() === 1 && await byLabel.getAttribute('type') === 'tel');
    await dialog.locator('label[for="qc-phone"]').click();
    check(`${width}px: clicking "Phone *" puts the cursor in the number box`,
      await page.evaluate(() => document.activeElement?.id === 'qc-phone'));
    await page.keyboard.type('+61 491 570 737');
    await page.waitForTimeout(600);
    const country = await dialog.locator('.phone-input select').inputValue();
    check(`${width}px: a number typed there is read and checked`,
      country === 'AU' && (await dialog.textContent()).includes('Nobody is on file with this number.'), country);
  }
  await page.close();
}
await browser.close();

console.log(failures === 0
  ? '\nPASS: a custom instalment duration survives clicks beside it and keeps every digit; the Instalments tick only answers to itself; the Add a customer phone box sits inside the window at every width, is labelled, and leaves other screens alone'
  : `\nFAILED: ${failures} check(s)`);
process.exit(failures === 0 ? 0 : 1);
