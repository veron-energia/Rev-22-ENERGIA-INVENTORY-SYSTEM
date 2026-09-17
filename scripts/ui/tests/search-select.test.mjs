// The type-ahead that replaced the long <select>s.
//
// The real component is bundled and mounted in jsdom, so these assert what it
// actually renders. The case that prompted them: the Replacement bundle picker
// on a whole-bundle exchange, whose catalogue runs to names differing by a
// single word — "Bundle B with Therapy" against "Bundle B with Vouchers".
import test from 'node:test';
import assert from 'node:assert/strict';
import { build } from 'esbuild';
import { JSDOM } from 'jsdom';

const built = await build({
  stdin: {
    contents: `
      import React from 'react';
      import { createRoot } from 'react-dom/client';
      import { SearchSelect } from './src/components/SearchSelect';

      // Shaped like the reported catalogue, plus enough filler to pass the cap.
      const BUNDLES = [
        { name: 'Energia Corporate Bundle Sale - Package Bundle A with Therapy', code: 'CORP-A-T', price: 994 },
        { name: 'Energia Corporate Bundle Sale - Package Bundle A with Vouchers', code: 'CORP-A-V', price: 994 },
        { name: 'Energia 16th Anniversary Promotion Bundle C with Vouchers', code: 'ANN-C-V', price: 610 },
        { name: 'Beads & Bottle', code: 'BEADS', price: 176 },
        { name: 'Energia Gloves Promotion', code: 'GLOVES', price: 61 },
      ];
      const FILLER = Array.from({ length: 260 }, (_, i) => (
        { name: 'Energia Filler Bundle ' + (i + 1), code: 'FILL-' + (i + 1), price: 100 + i + 1 }));

      function Harness() {
        const [value, setValue] = React.useState('');
        const [changes, setChanges] = React.useState(0);
        const options = [...BUNDLES, ...FILLER].map(b => ({
          value: b.code,
          label: b.name + ' — S$' + b.price.toFixed(2),
          sublabel: b.code,
          search: b.name + ' ' + b.code,
          searchPrices: [b.price],
        }));
        return React.createElement('div', null,
          React.createElement(SearchSelect, {
            options, value,
            onChange: v => { setValue(v); setChanges(n => n + 1); },
            placeholder: 'Search bundle name, code or price…',
            emptyLabel: 'No bundle matches that name, code or price',
          }),
          React.createElement('output', { id: 'value' }, value),
          React.createElement('output', { id: 'changes' }, String(changes)));
      }
      window.__mount = () => createRoot(document.getElementById('root')).render(React.createElement(Harness));
    `,
    resolveDir: process.cwd(), loader: 'ts',
  },
  bundle: true, write: false, format: 'iife', jsx: 'automatic',
  loader: { '.css': 'empty' },
  // SearchSelect shares a module with CustomerSearchSelect, which pulls in the
  // Supabase client. SearchSelect itself never calls the server — it filters
  // options it was handed — so the client is stubbed rather than configured:
  // the test then proves the filtering is local, and opens no sockets or
  // refresh timers that would keep the runner alive.
  plugins: [{
    name: 'stub-supabase',
    setup(b) {
      b.onResolve({ filter: /(^|\/)lib\/supabase$/ }, () => ({ path: 'supabase-stub', namespace: 'stub' }));
      b.onLoad({ filter: /.*/, namespace: 'stub' }, () => ({
        contents: `export const supabase = new Proxy({}, { get() { throw new Error('SearchSelect queried the server'); } });`,
        loader: 'js',
      }));
    },
  }],
});
const bundle = built.outputFiles[0].text;

function mount() {
  const dom = new JSDOM('<!doctype html><div id="root"></div>', {
    runScripts: 'dangerously', pretendToBeVisual: true,
  });
  const { window } = dom;
  const script = window.document.createElement('script');
  script.textContent = bundle;
  window.document.body.appendChild(script);
  window.__mount();
  return window;
}
const settle = () => new Promise(r => setTimeout(r, 40));

/** Open the dropdown and type a query into its search box. */
async function search(w, query) {
  await settle();                       // let the first render land
  w.document.querySelector('button').click();
  await settle();
  const box = w.document.querySelector('input');
  // Setting .value directly does not reach a React controlled input; the value
  // has to go through the native setter for React's own tracker to see it.
  Object.getOwnPropertyDescriptor(w.HTMLInputElement.prototype, 'value').set.call(box, query);
  box.dispatchEvent(new w.Event('input', { bubbles: true }));
  await settle();
  return box;
}
/** Only what the component rendered — <body> also holds the injected bundle. */
const rendered = w => w.document.getElementById('root').textContent;
/** The dropdown panel: search box → its relative wrapper → sticky header → panel. */
const panel = w => w.document.querySelector('input').parentElement.parentElement.parentElement;
/** The option rows only — not the sticky search header, the clear row (which
 *  leads with an icon) or the cap notice (which is bare text). */
const rows = w => [...panel(w).children]
  .filter(d => d.firstElementChild?.tagName === 'DIV' && !d.querySelector('input'))
  .map(d => d.textContent);

test('the list is closed until asked for, and shows the placeholder', async () => {
  const w = mount(); await settle();
  assert.equal(w.document.querySelectorAll('input').length, 0, 'no search box before opening');
  assert.match(w.document.querySelector('button').textContent, /Search bundle name, code or price/);
});

test('typing narrows a catalogue of near-identical names to the one wanted', async () => {
  const w = mount();
  await search(w, 'Bundle A with Vouchers');
  const found = rows(w);
  assert.equal(found.length, 1, `expected one match, got ${found.length}`);
  assert.match(found[0], /Package Bundle A with Vouchers/);
});

test('a bundle is findable by its code', async () => {
  const w = mount();
  await search(w, 'ANN-C-V');
  const found = rows(w);
  assert.equal(found.length, 1);
  assert.match(found[0], /16th Anniversary Promotion Bundle C with Vouchers/);
});

test('a bundle is findable by its exact price, in any currency spelling', async () => {
  for (const query of ['994', '994.00', 'S$994']) {
    const w = mount();
    await search(w, query);
    const found = rows(w);
    assert.equal(found.length, 2, `"${query}" matched ${found.length} bundles, expected the two at S$994`);
    assert.ok(found.every(t => /S\$994\.00/.test(t)), `"${query}" matched something not priced 994`);
  }
});

test('a query matching nothing says so rather than showing an empty box', async () => {
  const w = mount();
  await search(w, 'Sleeping System Emperor');
  assert.equal(rows(w).length, 0);
  assert.match(rendered(w), /No bundle matches that name, code or price/);
});

test('choosing an option reports it once and closes the list', async () => {
  const w = mount();
  await search(w, 'Beads');
  const row = [...panel(w).children].find(d => /Beads & Bottle/.test(d.textContent));
  row.click(); await settle();
  assert.equal(w.document.querySelector('#value').textContent, 'BEADS');
  assert.equal(w.document.querySelector('#changes').textContent, '1');
  assert.equal(w.document.querySelectorAll('input').length, 0, 'the list stayed open after choosing');
});

test('a capped list says how many matches it is not showing', async () => {
  const w = mount();
  await search(w, 'Energia');           // 264 of the 265 options
  assert.equal(rows(w).length, 200, 'the cap should still bound what is rendered');
  // Read the notice element itself: the panel's text runs the rows together, so
  // a regex over the whole panel picks up digits from the row above it.
  const notice = panel(w).lastElementChild.textContent;
  assert.match(notice, /more matches are not shown/, 'a capped list must say that it is capped');
  assert.equal(Number(notice.match(/^(\d+) more/)[1]), 64,
    'the count must be the real remainder, not a guess');
});

test('a list inside the cap says nothing about hidden matches', async () => {
  const w = mount();
  await search(w, 'Corporate');
  assert.ok(rows(w).length > 0 && rows(w).length < 200);
  assert.doesNotMatch(rendered(w), /not shown/,
    'a complete list must not imply something is missing');
});
