// The Commissions page's Rates window rules (AFFILIATES-M2): src/lib/commissionRates.ts.
// A blank box is refused, not saved as 0; a real 0 shows as "0"; only 0 to
// 100 with up to 3 decimals; nothing changed means nothing to save; the
// old → new list names each rate that changes. The settings row must hold
// all four rates, or there is nothing to edit. When the saved rates change
// while the window is open, a box left alone takes the new rate and a box
// changed keeps what was typed.
//
// Run: node --test scripts/commissions/tests/rates-form.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { build } from 'esbuild';

const compiled = await build({ stdin: { contents: "export * from './src/lib/commissionRates';", resolveDir: process.cwd(), loader: 'ts' },
  bundle: true, write: false, format: 'esm' });
const { ratesFromSettings, rateText, draftFromRates, parseRate, checkRatesDraft, changeLine, RATE_KEYS, sameRates, rebaseDraft } =
  await import('data:text/javascript;base64,' + Buffer.from(compiled.outputFiles[0].text).toString('base64'));

const SAVED = { t1_own: 15, t1_third: 4.5, t2_own: 35, t2_third: 35 };
const ROW = { commission_tier1_own_rate: '15', commission_tier1_third_rate: '4.5', commission_tier2_own_rate: '35', commission_tier2_third_rate: 35 };

test('the saved rates are read from the settings row, and a row missing one gives none', () => {
  assert.deepEqual(ratesFromSettings(ROW), SAVED);
  assert.deepEqual(ratesFromSettings({ ...ROW, commission_tier2_own_rate: '0' }), { ...SAVED, t2_own: 0 });
  assert.equal(ratesFromSettings(null), null);
  assert.equal(ratesFromSettings({ ...ROW, commission_tier2_own_rate: null }), null);
  assert.equal(ratesFromSettings({ ...ROW, commission_tier1_third_rate: 'abc' }), null);
});

test('0 shows as "0", never blank', () => {
  assert.equal(rateText(0), '0');
  assert.deepEqual(draftFromRates({ ...SAVED, t2_third: 0 }), { t1_own: '15', t1_third: '4.5', t2_own: '35', t2_third: '0' });
});

test('a box takes a number from 0 to 100 with up to 3 decimals', () => {
  for (const [t, v] of [['0', 0], ['100', 100], [' 4.5 ', 4.5], ['12.125', 12.125], ['.5', 0.5]]) assert.deepEqual(parseRate(t), { value: v, error: null }, t);
  assert.equal(parseRate('').error, 'Enter a rate.');
  assert.equal(parseRate('   ').error, 'Enter a rate.');
  for (const t of ['abc', '-1', '1e2', '4,5', '4.1234', '5%']) assert.equal(parseRate(t).error, 'Enter a number, like 15 or 4.5.', t);
  assert.equal(parseRate('100.5').error, 'Enter a rate from 0 to 100.');
});

test('a blank box blocks Save instead of saving 0', () => {
  const r = checkRatesDraft(SAVED, { t1_own: '15', t1_third: '4.5', t2_own: '', t2_third: '35' });
  assert.equal(r.rates, null);
  assert.deepEqual(Object.keys(r.errors), ['t2_own']);
  assert.deepEqual(r.changes, []);
});

test('nothing changed: nothing to save; a change lists old and new', () => {
  assert.deepEqual(checkRatesDraft(SAVED, draftFromRates(SAVED)).changes, []);
  const r = checkRatesDraft(SAVED, { t1_own: '15.0', t1_third: '4.5', t2_own: '30', t2_third: '0' });
  assert.deepEqual(r.rates, { t1_own: 15, t1_third: 4.5, t2_own: 30, t2_third: 0 });
  assert.deepEqual(r.changes.map(changeLine), ['Tier 2 — Own: 35% → 30%', 'Tier 2 — Third-party: 35% → 0%']);
  assert.deepEqual(RATE_KEYS, ['t1_own', 't1_third', 't2_own', 't2_third']);
});

test('rates saved by someone else while the window was open: boxes left alone take them, changed boxes keep the typing', () => {
  assert.equal(sameRates(SAVED, { ...SAVED }), true);
  assert.equal(sameRates(SAVED, { ...SAVED, t2_own: 30 }), false);
  const now = { ...SAVED, t2_own: 30, t1_third: 5 };
  const draft = { t1_own: '16', t1_third: '4.5', t2_own: '35.0', t2_third: '' };
  assert.deepEqual(rebaseDraft(SAVED, now, draft), { t1_own: '16', t1_third: '5', t2_own: '30', t2_third: '' });
  // Saved again on what they show: only the typed change is listed.
  const r = checkRatesDraft(now, { ...rebaseDraft(SAVED, now, draft), t2_third: '35' });
  assert.deepEqual(r.changes.map(changeLine), ['Tier 1 — Own: 15% → 16%']);
});
