/**
 * The invoice list must never read the customers table end to end.
 *
 * It used to. `fetchAllFrom('customers', '*')` pages in thousand-row windows,
 * one request after the next — fifteen serial requests and about ten megabytes
 * on a fourteen-thousand-customer database — purely to put a name in a column
 * the list query already fills in. It got slower every time a customer was
 * added, which is how the fault was reported.
 *
 * These are source assertions rather than behavioural ones because the thing
 * worth protecting is an absence: no test of the rendered page can prove a
 * request was not made on a larger table than the fixture.
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const page = readFileSync(new URL('../../../src/pages/InvoicesPage.tsx', import.meta.url), 'utf8');
const rpc  = readFileSync(new URL('../../../supabase/324_invoice_list_pagination.sql', import.meta.url), 'utf8');

test('the page never pages through the whole customers table', () => {
  const bulk = page.match(/fetchAll(?:From|Rows)[^\n]*customers/g) ?? [];
  assert.deepEqual(bulk, [], `whole-table customer reads reintroduced: ${bulk.join(' | ')}`);
});

test('every customer read is narrowed to named ids', () => {
  const reads = page.match(/from\('customers'\)[\s\S]{0,220}?(?=;|\n\s*\n)/g) ?? [];
  assert.ok(reads.length > 0, 'expected the page to still read customers by id');
  for (const read of reads) {
    assert.match(read, /\.(in|eq)\(/, `an unnarrowed customers read: ${read.slice(0, 120)}`);
    assert.doesNotMatch(read, /select\('\*'\)/, `a customers read still asks for every column: ${read.slice(0, 120)}`);
  }
});

test('the list query supplies the name the rows display', () => {
  assert.match(rpc, /c\.full_name\s+as\s+customer_name/,
    'invoice_list_page must return customer_name, or the rows have no name to show');
});

test('a row falls back to the name its own record carried', () => {
  assert.match(page, /const custName = \(id: string\) => customerOf\(id\)\?\.full_name \?\? nameById\[id\]/,
    'custName must fall back to the name the list row arrived with');
  assert.match(page, /rememberNames\(res\.rows as any\[\]\)/,
    'each loaded page must record the names it received');
});

test('the export labels rows from the export query, not from a cache', () => {
  assert.match(page, /header: 'Customer', value: \(i: any\) => i\.customer_name \?\? custName\(i\.customer_id\)/,
    'an export can cover more invoices than the page has cached names for');
});

test('a customer is not requested twice while the first request is in flight', () => {
  assert.match(page, /customerAskedRef/,
    'ensureCustomers needs an in-flight guard, or a re-running effect duplicates its request');
});
