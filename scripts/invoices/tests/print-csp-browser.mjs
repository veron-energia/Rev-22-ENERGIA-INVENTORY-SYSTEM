// Printing under an enforced Content-Security-Policy (security audit L8, step 2). The app will send
// `script-src 'self'` (no 'unsafe-inline'), and a window opened with window.open('', '_blank') and
// filled with document.write inherits it, so the inline <script> the print paths used to write into
// their print window would be blocked. Now the print window holds no script: the app (the opener)
// lays the sheets out on its document, then prints (src/lib/printWindow.ts).
//
// A tiny local server serves one page and the app code (printDoc.ts, printWindow.ts, printPages.mjs,
// creditBalanceLine.mjs, bundled) at the same origin: once WITH the header
// `Content-Security-Policy: script-src 'self'; style-src 'self' 'unsafe-inline'`, once without. Chrome
// runs headless; every document and name is invented.
//
// Checked, per case (a long two-copy sheet, an exchange-style one with credit block, a short one):
//  - the new flow under the header: no securitypolicyviolation event and no CSP console message in
//    either window, print called once, and the page count and sheet markup the same as the OLD inline
//    script gives for the same HTML on a page served without the header;
//  - the control: the old inline-script HTML under the header logs a CSP violation and does not
//    paginate (one sheet, print never called by it).
//
// Usage: node scripts/invoices/tests/print-csp-browser.mjs
import { build } from 'esbuild';
import { createRequire } from 'node:module';
import { createServer } from 'node:http';
import assert from 'node:assert/strict';
const require = createRequire(import.meta.url);
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || '/Users/shinthantaungstanley/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');

const CSP = "script-src 'self'; style-src 'self' 'unsafe-inline'";
const bundle = (await build({
  stdin: {
    contents: `
      import { printA5Document } from './src/lib/printDoc';
      import { printWhenReady } from './src/lib/printWindow';
      import { planCopyPages, paginatePrintCopies, PRINT_PAGES_SCRIPT } from './src/lib/invoices/printPages.mjs';
      import { fitCreditBalance, creditBalanceHtml, CREDIT_BALANCE_FIT_SCRIPT } from './src/lib/invoices/creditBalanceLine.mjs';
      window.__app = { printA5Document, printWhenReady, planCopyPages, paginatePrintCopies, fitCreditBalance, creditBalanceHtml,
        PRINT_PAGES_SCRIPT, CREDIT_BALANCE_FIT_SCRIPT };`,
    resolveDir: process.cwd(), loader: 'ts',
  },
  bundle: true, format: 'iife', write: false,
})).outputFiles[0].text;

const PNG = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==', 'base64');
const PAGE = '<!doctype html><html><head><meta charset="utf-8"><title>Opener</title></head><body><p>Opener</p><script src="/app.js"></script></body></html>';
const serve = withHeader => new Promise(resolve => {
  const server = createServer((req, res) => {
    const headers = withHeader ? { 'Content-Security-Policy': CSP } : {};
    if (req.url.startsWith('/late.png')) {   // a logo that arrives 1.5 s late
      setTimeout(() => { res.writeHead(200, { ...headers, 'Content-Type': 'image/png' }); res.end(PNG); }, 1500); return;
    }
    if (req.url === '/app.js') { res.writeHead(200, { ...headers, 'Content-Type': 'text/javascript' }); res.end(bundle); return; }
    res.writeHead(200, { ...headers, 'Content-Type': 'text/html; charset=utf-8' }); res.end(PAGE);
  }).listen(0, '127.0.0.1', () => resolve({ server, url: `http://127.0.0.1:${server.address().port}/` }));
});
const withCsp = await serve(true), without = await serve(false);

const browser = await chromium.launch({ headless: true, executablePath: process.env.CHROME_EXECUTABLE || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' });
let checks = 0;
const ok = (name, cond, detail) => { checks++; assert.ok(cond, `${name}${detail ? ' :: ' + detail : ''}`); console.log(`  ok  ${name}`); };

// ---- The document: invented, long enough for several sheets -------------------------------------
const POLICY = 'Items may be exchanged within 7 days with the receipt, after a check in store. Sample policy text for this test only.';
const doc = (n, logo) => ({
  docNo: 'INV-9001-0001', docTitle: 'Invoice',
  branding: { name: 'Sample Store', ...(logo ? { company_logo_url: logo } : {}), phone: '+61491570001', co_reg_no: 'SAMPLE001X' },
  headerLines: ['Date: 1 Jan 2027'], billToName: 'Sample Customer', billToLines: ['+61491570002'],
  lines: Array.from({ length: n }, (_, k) => ({ name: `Sample Item ${k + 1}`, qty: 1, unit: 10, total: 10, subLines: k % 5 === 0 ? ['Sample Content A', 'Sample Content B'] : [] })),
  totals: [{ label: 'Total', value: `S$${n * 10}.00`, grand: true }], payments: [['Cash', `S$${n * 10}.00`]],
  extraBlocks: [], signedByName: 'Sample Staff', policyText: POLICY,
});

/** A page of the app's origin, its console and violation events collected. */
async function openApp(_unused, url) {
  // A context of its own, so that its pages (the opener and the print window it opens) are all watched from creation.
  const context = await browser.newContext({ viewport: { width: 1123, height: 794 } });
  const cspConsole = [], errors = [];
  context.on('page', p => {
    p.on('console', m => { if (/content security policy/i.test(m.text())) cspConsole.push(m.text()); });
    p.on('pageerror', e => errors.push(e.message));
  });
  const page = await context.newPage();
  page.setDefaultTimeout(15000);
  page.cspConsole = cspConsole; page.errors = errors;
  await page.addInitScript(() => {
    window.__violations = [];
    document.addEventListener('securitypolicyviolation', e => window.__violations.push(`${e.violatedDirective} ${e.blockedURI}`));
  });
  await page.goto(url);
  await page.waitForFunction(() => !!window.__app);
  return page;
}

/**
 * Opens the print window the way the app does and writes `html` into it, with print stubbed on
 * the window (recorded as __prints). Returns the HTML the writer gave, if `writer` is 'app'.
 * writer: 'printA5' = the real printA5Document (new flow, no script); 'steps' = the invoice's flow
 * (the HTML written, then printWhenReady with the pages then the credit block); 'old' = the old
 * inline script appended to the HTML, run by the window itself.
 */
async function openPrint(page, { writer, d, html, credit }) {
  const popup = page.waitForEvent('popup');
  const done = page.evaluate(async ({ writer, d, html, credit }) => {
    const A = window.__app;
    const realOpen = window.open.bind(window);
    window.__prints = 0; window.__written = null;
    window.open = (...a) => {
      const w = realOpen(...a);
      w.__prints = 0;
      w.print = () => { w.__prints++; w.__imagesDone = [...w.document.images].every(i => i.complete && i.naturalWidth > 0); w.__imageCount = w.document.images.length; };   // the real print dialog would block the test
      const write = w.document.write.bind(w.document);
      w.document.write = s => { window.__written = s; return write(s); };
      window.__w = w;
      return w;
    };
    if (writer === 'printA5') {
      A.printA5Document(d);
    } else if (writer === 'steps') {
      const w = window.open('', '_blank');
      w.document.write(html); w.document.close();
      A.printWhenReady(w, [x => A.paginatePrintCopies(A.planCopyPages, x), x => A.fitCreditBalance(x)]);
    } else {
      const w = window.open('', '_blank');
      const script = `<script>${A.PRINT_PAGES_SCRIPT}\n${credit ? A.CREDIT_BALANCE_FIT_SCRIPT : ''}\n`
        + `window.onload=function(){try{paginatePrintCopies(planCopyPages);}catch(e){}${credit ? 'try{fitCreditBalance();}catch(e){}' : ''}window.print();}<\/script>`;
      w.document.write(html.replace('</body>', script + '</body>')); w.document.close();
    }
    return window.__written;
  }, { writer, d, html, credit });
  const w = await popup;
  const written = await done;
  return { w, written };
}

const state = page => page.evaluate(() => {
  const w = window.__w;
  const doc = w.document;
  const clone = doc.documentElement.cloneNode(true);
  for (const s of clone.querySelectorAll('script')) s.remove();
  return { prints: w.__prints, imagesDone: w.__imagesDone, imageCount: w.__imageCount, sheets: doc.querySelectorAll('.sheet').length, markup: clone.querySelector('body').innerHTML,
    credit: [...doc.querySelectorAll('.credit-balance')].map(b => getComputedStyle(b).display === 'none' ? 'none'
      : (b.querySelector('.credit-detail') && getComputedStyle(b.querySelector('.credit-detail')).display === 'none') ? 'total' : 'full'),
    scripts: doc.querySelectorAll('script').length, violations: window.__violations.length };
});
const settle = (page, prints) => page.waitForFunction(n => window.__w.__prints >= n, prints);

try {
  const ctx = await browser.newContext({ viewport: { width: 1123, height: 794 } });

  // A credit block as the invoice prints it (creditBalanceHtml), with a tall spacer so that the fit has work to do.
  const cases = [
    ['a long invoice, 60 lines (several sheets)', doc(60), false],
    ['a short invoice, 4 lines (one sheet, laid out as before)', doc(4), false],
    ['a long invoice with a credit block, the invoice path (pages, then the credit fit)', doc(45), true],
    ['a long invoice whose logo arrives 1.5 s late', null, false, true],
  ];
  for (const [name, d0, credit, late] of cases) {
    const origin = u => u.replace(/\/$/, '');
    const d = late ? doc(60, `${origin(withCsp.url)}/late.png?n=new`) : d0;
    // The same HTML for both flows: what printA5Document writes, with a credit block in the tail when asked.
    const line = { label: 'Credit balance (as at 1 Jan 2027)', amount: 'S$350.00', detail: 'Paid S$300.00 · Bonus S$50.00' };
    const dd = credit ? { ...d, extraBlocks: [] } : d;
    // Take the HTML from the real printA5Document on a page without the header.
    const probe = await openApp(ctx, without.url);
    const { written } = await openPrint(probe, { writer: 'printA5', d: late ? doc(60, `${origin(without.url)}/late.png?n=probe`) : dd });
    await settle(probe, 1);
    let html = late ? written.replaceAll(`${origin(without.url)}/late.png?n=probe`, 'ORIGIN/late.png') : written;
    if (credit) html = html.replaceAll('<div class="signrow">', `${await probe.evaluate(l => window.__app.creditBalanceHtml(l), line)}<div class="signrow">`);
    await probe.context().close();
    assert.ok(html && !/<script/i.test(html), 'printA5Document writes no script');

    // The old flow, in a page served WITHOUT the header: the reference.
    const ref = await openApp(ctx, without.url);
    await openPrint(ref, { writer: 'old', html: late ? html.replaceAll('ORIGIN', origin(without.url)) : html, credit });
    await settle(ref, 1);
    const was = await state(ref);

    // The new flow, in a page served WITH the header.
    const now = await openApp(ctx, withCsp.url);
    const app = credit ? 'steps' : 'printA5';
    const { written: wrote } = await openPrint(now, credit ? { writer: 'steps', html } : { writer: 'printA5', d: dd });
    await settle(now, 1);
    await now.waitForTimeout(300);   // nothing may print twice
    const is = await state(now);
    const viol = await now.evaluate(() => window.__violations);

    ok(`${name}: the print window holds no script`, is.scripts === 0 && !/<script/i.test(wrote ?? html));
    ok(`${name}: no CSP violation event and no CSP console message, in either window`,
      viol.length === 0 && is.violations === 0 && now.cspConsole.length === 0 && now.errors.length === 0, JSON.stringify([viol, now.cspConsole, now.errors]));
    ok(`${name}: print called once`, is.prints === 1 && was.prints === 1, `${is.prints} / ${was.prints}`);
    ok(`${name}: ${is.sheets} sheet(s), as the old inline script gives without the header (${was.sheets})`, is.sheets === was.sheets && (d.lines.length < 20 || is.sheets > 1),
      `${is.sheets} vs ${was.sheets}`);
    const norm = m => m.replace(/http:\/\/127\.0\.0\.1:\d+/g, 'ORIGIN').replace(/late\.png\?n=\w+/g, 'late.png');
    ok(`${name}: the sheet markup is the same, byte for byte`, norm(is.markup) === norm(was.markup) && JSON.stringify(is.credit) === JSON.stringify(was.credit),
      `${is.markup.length} vs ${was.markup.length}; credit ${JSON.stringify(is.credit)} vs ${JSON.stringify(was.credit)}`);
    if (late) ok(`${name}: print waited for the logo (complete, with a width, when print was called)`, was.imageCount >= 2 && is.imageCount === was.imageCount && is.imagesDone === true && was.imagesDone === true,
      JSON.stringify({ is: [is.imageCount, is.imagesDone], was: [was.imageCount, was.imagesDone] }));
    if (credit) ok(`${name}: the credit block is there to fit`, is.credit.length === 2 && is.credit.every(c => c !== undefined));

    // The control: the old inline-script HTML under the header is blocked and does not paginate.
    const ctl = await openApp(ctx, withCsp.url);
    const { w: ctlW } = await openPrint(ctl, { writer: 'old', html: late ? html.replaceAll('ORIGIN', origin(withCsp.url)) : html, credit });
    await ctl.waitForTimeout(800);
    const ctlState = await state(ctl).catch(e => ({ error: String(e) }));
    ok(`${name}: control, the old inline script under the header logs a CSP violation`, ctl.cspConsole.length > 0, JSON.stringify(ctl.cspConsole));
    ok(`${name}: control, and does not paginate or print`, ctlState.sheets === 1 && ctlState.prints === 0, JSON.stringify({ sheets: ctlState.sheets, prints: ctlState.prints }));
    await ctlW.close().catch(() => {});
    for (const p of [ref, now, ctl]) await p.context().close();
    void app;
  }

  // The window closed before it was ready: nothing prints, nothing throws.
  {
    const p = await openApp(ctx, withCsp.url);
    const r = await p.evaluate(async () => {
      const A = window.__app;
      const w = window.open('', '_blank');
      let prints = 0; w.print = () => { prints++; };
      w.document.write('<!doctype html><title>x</title><div class="sheet"></div>'); w.document.close();
      w.close();
      await new Promise(res => setTimeout(res, 100));
      A.printWhenReady(w, [x => A.paginatePrintCopies(A.planCopyPages, x)], 200);
      await new Promise(res => setTimeout(res, 500));
      return { prints, closed: w.closed };
    });
    ok('a window closed before the steps ran: no print, no error', r.closed && r.prints === 0 && p.errors.length === 0, JSON.stringify(r));
    await p.context().close();
  }
  console.log(`\nPASS print-csp-browser: ${checks} checks`);
} finally {
  await browser.close();
  withCsp.server.close(); without.server.close();
}
