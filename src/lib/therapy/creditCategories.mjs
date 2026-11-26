// What a credit spending category is called on screen (credit_spendable_categories): the Rules
// window's boxes and the credit-package form's "What this package's credit buys".
//
// Most read as their name with spaces (own_product -> "Own product"). 544 (the owner, 26 Nov
// 2026) added special_product and consignment_product, which read "Special products" and
// "Consignment products".

/** @type {Readonly<Record<string, string>>} */
const NAMED = Object.freeze({
  special_product: 'Special products',
  consignment_product: 'Consignment products',
});

/** The category's name, starting with a capital: "Own product", "Special products". */
export function creditCategoryLabel(category) {
  const c = String(category ?? '');
  if (Object.prototype.hasOwnProperty.call(NAMED, c)) return NAMED[c];
  return c.replace(/_/g, ' ').replace(/^\w/, s => s.toUpperCase());
}

/** The same in lower case, for use inside a sentence: "own product", "special products". */
export function creditCategoryWords(category) {
  return creditCategoryLabel(category).toLowerCase();
}
