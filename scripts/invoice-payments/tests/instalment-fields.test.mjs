// The instalment portion's rules and fields, exercised for real.
//
// The database checks all of this again (instalment-portions.sql); these
// assertions cover what a person sees and is stopped from doing before the
// round trip.
import { JSDOM } from 'jsdom';
import { build } from 'esbuild';
import assert from 'node:assert/strict';

const dom = new JSDOM('<!doctype html><html><body><div id="root"></div></body></html>',
  { url: 'https://tests.invalid', pretendToBeVisual: true });
for (const k of ['window', 'document', 'navigator', 'HTMLElement', 'Element', 'Node', 'Event',
                 'KeyboardEvent', 'MouseEvent', 'getComputedStyle', 'requestAnimationFrame',
                 'cancelAnimationFrame']) {
  try { globalThis[k] = dom.window[k]; }
  catch { Object.defineProperty(globalThis, k, { value: dom.window[k], configurable: true, writable: true }); }
}
globalThis.IS_REACT_ACT_ENVIRONMENT = true;

const built = await build({
  stdin: {
    contents: `
      export * from './src/components/invoices/InstalmentPortionFields';
      export { createRoot } from 'react-dom/client';
      export { act } from 'react-dom/test-utils';
      export { default as React } from 'react';`,
    resolveDir: process.cwd(), loader: 'ts',
  },
  bundle: true, write: false, format: 'esm', jsx: 'automatic',
  define: { 'process.env.NODE_ENV': '"development"' },
  plugins: [{ name: 'stub', setup(b) {
    b.onResolve({ filter: /(^|\/)supabase$/ }, () => ({ path: 'stub', namespace: 'st' }));
    b.onLoad({ filter: /.*/, namespace: 'st' }, () => ({
      contents: 'export const supabase = { rpc: async () => ({ data: null, error: null }) };', loader: 'js' }));
  } }],
});
const m = await import('data:text/javascript;base64,' + Buffer.from(built.outputFiles[0].text).toString('base64'));
const { InstalmentPortionFields, INSTALMENT_METHOD, emptyPortion, portionProblem, createRoot, act, React } = m;

let failures = 0;
const check = (name, cond, detail) => {
  if (cond) console.log(`  ok   ${name}`);
  else { failures++; console.log(`  FAIL ${name}${detail ? ' — ' + detail : ''}`); }
};

// ---- the rules -----------------------------------------------------------
// An instalment is a label on money that has arrived (326): one amount, the
// real method it came through, and a duration for the record.
const ok = { method_id: 'pm-1', months: 12 };
check('a complete instalment with money is accepted', portionProblem(ok, 1080) === null);
check('a missing underlying method is caught', /actually comes through/.test(portionProblem({ ...ok, method_id: '' }, 1080)));
check('instalment cannot be its own method',
  /its own payment method/.test(portionProblem({ ...ok, method_id: INSTALMENT_METHOD }, 1080)));
check('zero months is caught', /positive whole number/.test(portionProblem({ ...ok, months: 0 }, 1080)));
check('a fractional duration is caught', /positive whole number/.test(portionProblem({ ...ok, months: 2.5 }, 1080)));
check('an amount is required: nothing received is no longer the normal case',
  /amount received/.test(portionProblem(ok, 0)));
check('a negative amount is refused the same way', /amount received/.test(portionProblem(ok, -5)));
check('the default portion still needs a method', portionProblem(emptyPortion, 100) !== null);

// ---- the fields ----------------------------------------------------------
const root = createRoot(document.getElementById('root'));
let value = { ...emptyPortion };
let received = 0;
const render = async () => {
  await act(async () => {
    root.render(React.createElement(InstalmentPortionFields, {
      value, onChange: v => { value = v; }, receivedNow: received,
      onReceivedNow: n => { received = n; },
      methods: [
        { id: 'pm-1', name: 'Master Card' },
        { id: 'pm-2', name: 'PayNow' },
        { id: 'pm-3', name: 'Store Wallet', is_wallet_credit: true },
        { id: 'pm-4', name: 'Retired', deleted_at: '2020-01-01' },
      ],
      error: null,
    }));
  });
  await act(async () => { await new Promise(r => setTimeout(r, 0)); });
};
await render();
const text = () => document.body.textContent;

check('no category is offered any more: every instalment is in-house',
  !text().includes('Provider-funded') && !text().includes('Category'));
check('the presets are offered', [3, 6, 9, 12].every(n =>
  Array.from(document.querySelectorAll('.instalment-months .btn')).some(b => b.textContent.trim() === String(n))));
check('a custom duration can be typed',
  !!document.querySelector('.instalment-months input[type="number"]'));
check('one amount is asked for, not a covered sum and a deposit',
  text().includes('Amount') && !text().includes('Amount covered by this arrangement') && !text().includes('Amount actually received now'));
check('the current preset is marked for assistive technology',
  !!document.querySelector('.instalment-months .btn[aria-pressed="true"]'));

// Wallet credit and retired methods are not instalment channels, and the
// arrangement can never choose itself.
const options = Array.from(document.querySelectorAll('option, [role="option"]')).map(o => o.textContent);
check('wallet credit is not offered as the underlying method',
  !options.some(o => (o ?? '').includes('Store Wallet')), options.join('|'));
check('a retired method is not offered', !options.some(o => (o ?? '').includes('Retired')));
check('Instalment is not offered as its own method',
  !options.some(o => (o ?? '').toLowerCase().includes('instalment — pay over time')));

// The wording says what the amount is: money that settles the invoice today.
check('the amount is explained as settling the invoice today',
  text().includes('settles the') && text().includes('nothing is left outstanding'));

console.log(failures === 0
  ? '\nPASS: instalment rules reject every incomplete or recursive portion and require an amount, the fields offer no category, four presets, a custom duration and a single amount that settles the invoice today'
  : `\nFAILED: ${failures} check(s)`);
process.exit(failures === 0 ? 0 : 1);
