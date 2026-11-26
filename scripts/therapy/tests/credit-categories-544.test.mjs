// 544 (the owner, 26 Nov 2026): the credit spending categories as staff read them. The two new
// ones read "Special products" and "Consignment products" (never "unknown" or the raw name);
// every older one reads as before (its name with spaces); the Rules window and the
// credit-package form both use these words.
//   node --test scripts/therapy/tests/credit-categories-544.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { creditCategoryLabel, creditCategoryWords } from '../../../src/lib/therapy/creditCategories.mjs';

// credit_spendable_categories() after 544, in its order.
const SPENDABLE = ['therapy_session', 'unlimited_therapy', 'session_voucher', 'money_voucher', 'own_product',
  'third_party_product', 'other_product', 'promotion', 'event_ticket', 'special_product', 'consignment_product'];

test('the two new categories read properly', () => {
  assert.equal(creditCategoryLabel('special_product'), 'Special products');
  assert.equal(creditCategoryLabel('consignment_product'), 'Consignment products');
  assert.equal(creditCategoryWords('special_product'), 'special products');
  assert.equal(creditCategoryWords('consignment_product'), 'consignment products');
});

test('every older category reads as it did before 544', () => {
  const before = c => c.replace(/_/g, ' ').replace(/^\w/, s => s.toUpperCase());
  for (const c of SPENDABLE.slice(0, 9)) {
    assert.equal(creditCategoryLabel(c), before(c), c);
    assert.equal(creditCategoryWords(c), c.replace(/_/g, ' '), c);
  }
});

test('no category on the Rules screen reads as unknown or with an underscore', () => {
  for (const c of SPENDABLE) {
    assert.doesNotMatch(creditCategoryLabel(c), /unknown|_/i, c);
  }
  assert.equal(creditCategoryLabel(undefined), '');
});

test('the Rules window, rendered, offers both new boxes by name and shows them in the preview', async () => {
  const { setupDom, bundle, driver, fakeSupabase } = await import('../../ui/page-harness.mjs');
  const dom = setupDom();
  const mod = await bundle(`
    export { CreditSpendingRules } from './src/components/therapy/CreditSpendingRules';
    export { act } from 'react';
    export { createRoot } from 'react-dom/client';
    import React from 'react';
    export { React };
  `);
  const d = driver(mod, dom);
  try {
    globalThis.__supabase = fakeSupabase({ rpc: {
      credit_spendable_categories: () => SPENDABLE,
      credit_package_effective_rules: () => ({ paid: ['therapy_session'], bonus: ['own_product', 'third_party_product'], source: 'default' }),
      preview_credit_package_policy_change: a => ({
        before: { paid: ['therapy_session'], bonus: ['own_product', 'third_party_product'] },
        after: { paid: a.p_paid, bonus: a.p_bonus }, affected_customers: 0, affected_paid_credit: 0, affected_bonus_credit: 0 }),
    } });
    await d.mount(mod.React.createElement(mod.CreditSpendingRules,
      { packageId: 'pk-made-up', packageName: 'Made-up Package', canEdit: true, onClose: () => {} }));
    const paidSet = document.querySelector('.credit-rules-set');
    const names = [...paidSet.querySelectorAll('label')].map(l => l.textContent.trim());
    assert.ok(names.includes('Special products') && names.includes('Consignment products'), names.join(', '));
    assert.ok(!names.some(n => /unknown|_/i.test(n)), names.join(', '));
    const box = [...paidSet.querySelectorAll('label')].find(l => l.textContent.trim() === 'Consignment products').querySelector('input');
    await d.toggle(box);
    await d.click([...document.querySelectorAll('button')].find(b => /review/i.test(b.textContent)));
    assert.match(document.body.textContent, /Paid: Therapy session, Consignment products/);
  } finally {
    await d.unmount();
    dom.window.close();
  }
});

test('the Rules window and the credit-package form use these words', () => {
  const rules = readFileSync(new URL('../../../src/components/therapy/CreditSpendingRules.tsx', import.meta.url), 'utf8');
  assert.match(rules, /import \{ creditCategoryLabel \} from '\.\.\/\.\.\/lib\/therapy\/creditCategories\.mjs';/);
  assert.match(rules, /const label = creditCategoryLabel;/);
  const page = readFileSync(new URL('../../../src/pages/TherapyPage.tsx', import.meta.url), 'utf8');
  assert.match(page, /import \{ creditCategoryWords \} from '\.\.\/lib\/therapy\/creditCategories\.mjs';/);
  assert.match(page, /const categoryLabel = \(c: string\) => creditCategoryWords\(c\);/);
});
