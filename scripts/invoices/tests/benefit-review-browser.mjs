// Exercises the real historical-review component with synthetic, in-memory RPCs.
// All browser network requests are blocked. No credentials or database are used.
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { mkdir, readFile } from 'node:fs/promises';
import { build } from 'esbuild';

const require = createRequire(import.meta.url);
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || '/Users/shinthantaungstanley/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
const ids = {
  line: '00000000-0000-4000-8000-000000000001',
  sale: '00000000-0000-4000-8000-000000000002',
  paid: '00000000-0000-4000-8000-000000000003',
  bonus: '00000000-0000-4000-8000-000000000004',
  unrelated: '00000000-0000-4000-8000-000000000005',
};
const paid = { lot_id: ids.paid, customer_name: 'Historical Recipient', kind: 'paid_credit', granted_value: 100 };
const bonus = { lot_id: ids.bonus, customer_name: 'Historical Recipient', kind: 'bonus_credit', granted_value: 20 };
const line = {
  invoice_item_id: ids.line,
  name: 'Original credit package',
  external_paid: 100,
  review_note: 'Original values need supporting sale records.',
  blocked_reason: 'Verify the original bonus source before allocating paid values.',
  benefits: [paid],
  sources: [{
    sale_id: ids.sale,
    customer_name: 'Historical Recipient',
    paid_lot_id: ids.paid,
    bonus_lot_id: null,
    verified: false,
    candidates: [
      { lot_id: ids.unrelated, granted_value: 20, purchase_date: '2020-02-01' },
      { lot_id: ids.bonus, granted_value: 20, purchase_date: '2020-02-01' },
    ],
  }],
};
const blockedReason = 'Multiple invoice lines share this package. Resolve the exact sale-to-line mapping before recording historical benefit values.';
const mock = `export const supabase = {
  async rpc(name, args) {
    window.__calls.push({ name, args });
    if (name === 'invoice_benefit_review_options') return {
      data: structuredClone(window.__reviews[args.p_invoice_id]), error: null,
    };
    if (name === 'verify_invoice_credit_sale_sources') {
      const line = window.__reviews.review.lines[0];
      line.sources[0].verified = true;
      line.sources[0].bonus_lot_id = args.p_bonus_lot_id;
      line.blocked_reason = null;
      line.benefits.push(structuredClone(window.__bonus));
      return { data: null, error: null };
    }
    if (name === 'record_invoice_benefit_values') {
      if (window.__failNextSave) {
        window.__failNextSave = false;
        return { data: null, error: { message: 'Simulated save failure: your values were not recorded.' } };
      }
      window.__reviews.review.lines = [];
      return { data: null, error: null };
    }
    throw new Error('Unexpected RPC: ' + name);
  },
};`;
const result = await build({
  stdin: {
    contents: `import React from 'react';
      import { createRoot } from 'react-dom/client';
      import { InvoiceBenefitEvidenceReview } from './src/components/invoices/InvoiceBenefitEvidenceReview';
      const root = createRoot(document.getElementById('root'));
      window.__renderInvoice = invoiceId => root.render(<InvoiceBenefitEvidenceReview invoiceId={invoiceId} onChanged={async () => { window.__refreshes++; }} />);
      window.__renderInvoice('review');`,
    resolveDir: process.cwd(), loader: 'tsx',
  },
  bundle: true, format: 'iife', write: false,
  plugins: [{ name: 'offline-review-rpc', setup(builder) {
    builder.onResolve({ filter: /(?:^|\/)supabase$/ }, () => ({ path: 'mock', namespace: 'fixture' }));
    builder.onLoad({ filter: /.*/, namespace: 'fixture' }, () => ({ contents: mock, loader: 'js' }));
  } }],
});
const css = (await readFile('src/styles/globals.css', 'utf8') + '\n' +
  await readFile('src/components/invoices/invoice-controls.css', 'utf8')).replace(/^@import.*$/gm, '');
await mkdir('.invoice-test/browser', { recursive: true });
const browser = await chromium.launch({
  headless: true,
  executablePath: process.env.CHROME_EXECUTABLE || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
});
try {
  const page = await browser.newPage({ viewport: { width: 320, height: 850 }, isMobile: true, hasTouch: true });
  page.setDefaultTimeout(8000);
  const errors = [];
  page.on('pageerror', error => errors.push(error.message));
  await page.route('**/*', route => route.request().url() === 'https://invoice-review.test/'
    ? route.fulfill({ contentType: 'text/html', body: '<html><head><meta name="viewport" content="width=device-width,initial-scale=1"></head><body><main style="padding:12px"><div id="root"></div></main></body></html>' })
    : route.abort());
  await page.goto('https://invoice-review.test/');
  await page.evaluate(({ line, paid, bonus, blockedReason }) => {
    window.__calls = [];
    window.__refreshes = 0;
    window.__failNextSave = true;
    window.__bonus = bonus;
    window.__reviews = {
      review: { lines: [line] },
      blocked: { lines: [{ ...line, invoice_item_id: 'blocked-line', name: 'Unresolved shared package', blocked_reason: blockedReason, benefits: [paid, bonus], sources: [] }] },
    };
  }, { line, paid, bonus, blockedReason });
  await page.addStyleTag({ content: css });
  await page.addScriptTag({ content: result.outputFiles[0].text });
  assert.equal(await page.evaluate(() => getComputedStyle(document.body).backgroundColor), 'rgb(246, 247, 245)', 'Use the real application CSS');

  const sourceChoice = page.getByRole('combobox', { name: /^Original bonus grant for Historical Recipient/ });
  const sourceEvidence = page.getByRole('textbox', { name: /^Source evidence for Historical Recipient/ });
  const verify = page.getByRole('button', { name: 'Save original source review', exact: true });
  const save = page.getByRole('button', { name: 'Save reviewed benefit values', exact: true });
  await sourceChoice.waitFor();
  assert.equal(await sourceChoice.inputValue(), '', 'Unknown source must start blank, including when a candidate has a matching date and amount');
  assert.equal(await sourceChoice.locator('option:checked').getAttribute('value'), '', 'Do not preselect no-bonus or the first grant');
  assert.ok(await verify.isDisabled(), 'Source verification needs an explicit choice and evidence');
  assert.ok(await save.isDisabled(), 'Unverified source blocks allocations');
  await sourceEvidence.fill('Original source records reviewed');
  assert.ok(await verify.isDisabled(), 'Evidence alone must not infer a bonus source');
  await sourceChoice.selectOption(ids.bonus);
  await sourceEvidence.fill('short');
  assert.ok(await verify.isDisabled(), 'Source evidence must contain at least ten characters');
  const sourceReason = 'Receipt ARCH-100 and original grant register explicitly identify this bonus lot.';
  await sourceEvidence.fill(`  ${sourceReason}  `);
  assert.ok(await verify.isEnabled());
  await checkFit(page, 'source-review');
  await page.screenshot({ path: '.invoice-test/browser/benefit-source-320.png', fullPage: true });
  await verify.click();

  const paidInput = page.getByRole('spinbutton', { name: /^Paid value for grant 1:/ });
  const bonusInput = page.getByRole('spinbutton', { name: /^Paid value for grant 2:/ });
  const evidence = page.getByRole('textbox', { name: /^Evidence for Original credit package/ });
  const confirm = page.getByRole('checkbox', { name: 'I confirm that this evidence includes every original paid-credit, bonus-credit and voucher grant for this invoice line.', exact: true });
  await bonusInput.waitFor();
  assert.equal(await paidInput.inputValue(), '', 'Do not suggest a paid allocation after source verification');
  assert.equal(await bonusInput.inputValue(), '', 'Do not prefill a zero bonus allocation');
  assert.ok(await save.isDisabled(), 'Blank allocations cannot be saved');
  assert.deepEqual(await page.evaluate(() => window.__calls.find(call => call.name === 'verify_invoice_credit_sale_sources').args), {
    p_sale_id: ids.sale, p_bonus_lot_id: ids.bonus, p_no_bonus: false, p_evidence: sourceReason,
  });
  assert.equal(await page.evaluate(() => window.__refreshes), 1, 'Source save refreshes the parent invoice');

  const allocationReason = 'Original receipt ARCH-100 and grant schedule allocate the paid value to every original grant.';
  await paidInput.fill('100');
  await evidence.fill(allocationReason);
  await confirm.check();
  assert.ok(await save.isDisabled(), 'A blank bonus value is not implicitly zero');
  await bonusInput.fill('0');
  assert.equal(await confirm.isChecked(), false, 'Changing paid values requires renewed confirmation');
  await confirm.check();
  assert.ok(await save.isEnabled(), 'An explicitly entered zero is a valid paid allocation');

  await paidInput.fill('83.33');
  await bonusInput.fill('16.66');
  await confirm.check();
  assert.ok(await save.isDisabled(), 'A one-cent shortfall must be rejected');
  await bonusInput.fill('16.67');
  assert.ok(await save.isDisabled(), 'Exact totals still require completeness confirmation');
  await evidence.fill('short');
  await confirm.check();
  assert.ok(await save.isDisabled(), 'Allocations still require supporting evidence');
  await evidence.fill(`  ${allocationReason}  `);
  await confirm.check();
  assert.ok(await save.isEnabled(), '83.33 plus 16.67 reconciles exactly to 100');
  await checkFit(page, 'paid-value-review');
  await page.screenshot({ path: '.invoice-test/browser/benefit-allocations-320.png', fullPage: true });
  await save.click();
  await page.getByRole('alert').filter({ hasText: 'Simulated save failure' }).waitFor();
  assert.equal(await paidInput.inputValue(), '83.33', 'Failed save preserves paid values');
  assert.equal(await bonusInput.inputValue(), '16.67', 'Failed save preserves bonus values');
  assert.equal(await evidence.inputValue(), `  ${allocationReason}  `, 'Failed save preserves evidence');
  assert.ok(await confirm.isChecked(), 'Failed save preserves confirmation');
  assert.ok(await save.isEnabled(), 'The reviewer can retry a failed save');
  await save.click();
  await page.getByRole('status').filter({ hasText: 'were saved to the audit history' }).waitFor();
  const recorded = await page.evaluate(() => window.__calls.filter(call => call.name === 'record_invoice_benefit_values'));
  const expected = { p_item_id: ids.line, p_allocations: [
    { lot_id: ids.paid, paid_value: 83.33, granted_value: 100 },
    { lot_id: ids.bonus, paid_value: 16.67, granted_value: 20 },
  ], p_evidence: allocationReason };
  assert.equal(recorded.length, 2, 'Only the failed save and explicit retry invoke the allocation RPC');
  assert.deepEqual(recorded.map(call => call.args), [expected, expected], 'Keep exact original IDs and values on retry');
  assert.equal(await page.evaluate(() => window.__refreshes), 2, 'Successful allocation save refreshes the parent once');
  assert.equal(await paidInput.count(), 0, 'Successful refresh removes the resolved review line');

  await page.evaluate(() => window.__renderInvoice('blocked'));
  await page.getByRole('alert').filter({ hasText: blockedReason }).waitFor();
  assert.ok(await save.isDisabled(), 'Ambiguous sale-to-line mapping remains pending review');
  for (const input of await page.getByRole('spinbutton').all()) assert.ok(await input.isDisabled(), 'Blocked mappings do not accept paid allocations');
  assert.equal(await page.evaluate(() => window.__calls.filter(call => call.name === 'record_invoice_benefit_values').length), 2, 'No allocation RPC for the blocked record');
  await checkFit(page, 'blocked-mapping');
  assert.deepEqual(errors, [], 'No browser runtime errors');
  console.log('PASS Chromium 320px: explicit source review, complete allocations including zero, cents reconciliation, evidence/confirmation, failure retention and retry, blocked mappings, and mobile fit');
} finally {
  await browser.close();
}

async function checkFit(page, stage) {
  assert.ok(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1), `${stage}: no horizontal page overflow at 320px`);
  for (const control of await page.locator('select, input[type="number"], textarea, button').all()) {
    await control.scrollIntoViewIfNeeded();
    const box = await control.boundingBox();
    assert.ok(box && box.x >= 0 && box.x + box.width <= 321, `${stage}: control fits the viewport: ${JSON.stringify(box)}`);
  }
}
