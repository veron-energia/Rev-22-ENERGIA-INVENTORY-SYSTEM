export type PricedSearchOption = { label: string; search?: string; searchPrices?: readonly (number | string | null | undefined)[] };

/** Exact currency comparison in cents. Non-price text still uses ordinary search. */
export function priceCents(value: string | number | null | undefined): number | null {
  if (value == null) return null;
  if (typeof value === 'number') {
    const cents = Math.round(value * 100);
    return value >= 0 && Number.isSafeInteger(cents) && Math.abs(value * 100 - cents) < 0.000001 ? cents : null;
  }
  const text = value.trim().replace(/\s/g, '').replace(/^(?:S\$|SGD|\$)/i, '');
  if (!/^(?:\d+|\d{1,3}(?:,\d{3})+)(?:\.\d{1,2})?$/.test(text)) return null;
  const [whole, decimal = ''] = text.replace(/,/g, '').split('.');
  const cents = Number(whole) * 100 + Number(decimal.padEnd(2, '0'));
  return Number.isSafeInteger(cents) ? cents : null;
}

export function searchCatalogueOptions<T extends PricedSearchOption>(options: T[], query: string): T[] {
  const text = query.trim().toLowerCase();
  if (!text) return options;
  const cents = priceCents(query);
  return options.map((option, index) => ({ option, index,
    exact: cents != null && !!option.searchPrices?.some(price => priceCents(price) === cents),
    textMatch: (option.search ?? option.label).toLowerCase().includes(text),
  })).filter(row => row.exact || row.textMatch)
    .sort((a, b) => Number(b.exact) - Number(a.exact) || a.index - b.index).map(row => row.option);
}
