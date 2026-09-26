/**
 * A saved correction says what it did to therapy (362).
 *
 * correct_invoice now closes the unused therapy of a line it removes or
 * changes, moves a unit to a line it added for the same package, and issues
 * therapy it swaps in when the invoice is paid. It returns the entitlement
 * numbers as { therapy: { closed, moved, issued } }. The correction form
 * closes on success and has no other success message, so without this notice
 * the operator would not know a customer's therapy changed.
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const page = readFileSync(new URL('../../../src/pages/InvoicesPage.tsx', import.meta.url), 'utf8');

// The helper, with its one type annotation removed, run as plain JavaScript.
const start = page.indexOf('const correctionTherapyNote = ');
assert.ok(start > 0, 'correctionTherapyNote not found');
const src = page.slice(start, page.indexOf('\n};', start) + 3)
  .replace(/\(t: [^)]*\): string \| null =>/, '(t) =>');
const correctionTherapyNote = new Function(`${src}; return correctionTherapyNote;`)();

test('it names what closed, moved and was issued, in that order', () => {
  assert.equal(
    correctionTherapyNote({ closed: ['UTP-0000014'], moved: ['UTP-0000015'], issued: ['UTP-0000016', 'UTP-0000017'] }),
    'This correction closed unused therapy UTP-0000014; moved UTP-0000015 to the new line; issued UTP-0000016, UTP-0000017.');
  assert.equal(correctionTherapyNote({ issued: ['UTP-0000016'] }), 'This correction issued UTP-0000016.');
});

test('nothing to say when the correction left therapy alone', () => {
  assert.equal(correctionTherapyNote({}), null);
  assert.equal(correctionTherapyNote(undefined), null);
  assert.equal(correctionTherapyNote({ closed: [] }), null);
});

test('the form shows it after a saved correction, and only then', () => {
  const save = page.indexOf("await supabase.rpc('correct_invoice'");
  const set = page.indexOf('setTherapyNote(correctionTherapyNote((data as any)?.therapy))');
  assert.ok(save > 0 && set > save, 'the note must be set from the correction result');
  assert.match(page.slice(set - 60, set), /if \(editingInvoiceId\) $/, 'only a correction sets the note');
  // after the error branch has returned
  assert.ok(page.lastIndexOf('if (error) {', set) > save, 'the note must come after the error check');
  assert.match(page, /data-testid="correction-therapy-note"[\s\S]{0,200}\{therapyNote\}[\s\S]{0,200}setTherapyNote\(null\)/,
    'the note is rendered and can be dismissed');
});
