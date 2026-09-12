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
const ok = { category: 'in_house', method_id: 'pm-1', months: 12, covered_amount: 900 };
check('a complete portion is accepted', portionProblem(ok, 0) === null);
check('a missing category is caught', /in-house or provider-funded/.test(portionProblem({ ...ok, category: '' }, 0)));
check('a missing underlying method is caught', /actually comes through/.test(portionProblem({ ...ok, method_id: '' }, 0)));
check('instalment cannot be its own method',
  /its own payment method/.test(portionProblem({ ...ok, method_id: INSTALMENT_METHOD }, 0)));
check('zero months is caught', /positive whole number/.test(portionProblem({ ...ok, months: 0 }, 0)));
check('a fractional duration is caught', /positive whole number/.test(portionProblem({ ...ok, months: 2.5 }, 0)));
check('a missing covered amount is caught', /amount this arrangement covers/.test(portionProblem({ ...ok, covered_amount: 0 }, 0)));
check('nothing received today is perfectly valid', portionProblem(ok, 0) === null);
check('a negative receipt is caught', /cannot be negative/.test(portionProblem(ok, -5)));
check('the default portion still needs a method', portionProblem(emptyPortion, 0) !== null);

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

check('both categories are offered',
  text().includes('In-house') && text().includes('Provider-funded'));
check('the presets are offered', [3, 6, 9, 12].every(n =>
  Array.from(document.querySelectorAll('.instalment-months .btn')).some(b => b.textContent.trim() === String(n))));
check('a custom duration can be typed',
  !!document.querySelector('.instalment-months input[type="number"]'));
check('the covered amount and the money received now are asked separately',
  text().includes('Amount covered by this arrangement') && text().includes('Amount actually received now'));
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

// In-house wording tells staff a promise is not money.
check('in-house explains that nothing has been paid yet',
  text().includes('the arrangement on its own settles nothing'));
value = { ...value, category: 'provider_funded' };
await render();
check('provider-funded explains it is a real settlement',
  text().includes('What the provider has actually settled'));

console.log(failures === 0
  ? '\nPASS: instalment rules reject every incomplete or recursive portion, the fields offer both categories, four presets and a custom duration, and keep the covered amount separate from money actually received'
  : `\nFAILED: ${failures} check(s)`);
process.exit(failures === 0 ? 0 : 1);
