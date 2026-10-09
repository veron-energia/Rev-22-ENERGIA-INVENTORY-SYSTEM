// What the invoice page's Xero sales export puts in the file, and what it tells
// the person first (411): planXeroSalesExport and its helpers.
//
//   node --test scripts/xero/tests/sales-export-plan.test.mjs
//
// Every number, name and amount is invented.
import test from 'node:test';
import assert from 'node:assert/strict';
import {
  EXPORTABLE_KINDS, amountCents, formatCents, sgd, dayLabel, momentLabel, singaporeDay, expectedDocumentNumber, eventKey,
  planXeroSalesExport, totalCents,
} from '../../../src/lib/xero/salesExport.mjs';

const ev = (id, amount, document_date, extra = {}) => ({
  event_kind: 'receipt', event_id: id, invoice_id: `inv-${id}`, invoice_no: `INV-${id}`, store_id: 'store-a',
  document_number: `INV-${id}-PAY-${id}`, document_date, amount, customer_id: null, contact_name: null,
  contact_email: null, contact_address: null, ...extra,
});
const download = (e, extra = {}) => ({ event_kind: e.event_kind, event_id: e.event_id, document_number: e.document_number,
  document_date: e.document_date, amount: e.amount, exported_at: '2026-09-01T02:00:00Z', times: 1, ...extra });
const augExport = { id: 'x-aug', exported_at: '2026-09-01T02:00:00Z', exported_by: 'Owner', from_date: '2026-08-01',
  to_date: '2026-08-31', store_id: null, covered_store_ids: ['store-a', 'store-b'], document_count: 3, net_total: 300 };
const review = over => ({ recorded_since: '2026-09-01T02:00:00Z', exports: [], downloads: [], vanished: [], missed: [], ...over });
const ids = list => list.map(e => e.event_id);

test('with nothing downloaded before, every exportable document goes in, sorted, and nothing needs reading', () => {
  const events = [ev('b', 20, '2026-08-02'), ev('a', 10, '2026-08-02'), ev('c', -5, '2026-08-01', { event_kind: 'refund' }),
    ev('l', 100, '2026-08-03', { event_kind: 'legacy_refund_left_out', document_number: null })];
  // Recording began before these dates, and nothing of them was downloaded since.
  const plan = planXeroSalesExport(events, review({ recorded_since: '2026-07-01T02:00:00Z' }), { from: '2026-08-01' });
  assert.deepEqual(ids(plan.include), ['c', 'a', 'b'], 'by date, then event');
  assert.deepEqual(ids(plan.legacy), ['l'], 'a payment refunded before refunds were recorded is shown, never exported');
  assert.equal(plan.unrecorded, false);
  assert.equal(plan.needsReview, false);
  assert.deepEqual([plan.already, plan.changed, plan.late, plan.missed, plan.vanished, plan.moved, plan.again],
    [[], [], [], [], [], [], []]);
});

test('dates from before the first recorded download (or with none recorded) must be checked in Xero first', () => {
  const events = [ev('a', 10, '2026-08-02')];
  for (const [r, from] of [[null, '2026-08-01'], [review({ recorded_since: null }), '2026-08-01'],
    [review({ recorded_since: '2026-07-01T02:00:00Z' }), null]]) {
    const plan = planXeroSalesExport(events, r, { from });
    assert.equal(plan.unrecorded, true);
    assert.equal(plan.needsReview, true, 'the old export may have put these documents in Xero');
    assert.deepEqual(ids(plan.include), ['a'], 'the documents still go in once confirmed');
  }
  assert.equal(planXeroSalesExport(events, null).recordedSince, null);
  // The first recorded download's Singapore day: dates starting on it are unrecorded, the day after are not.
  const r = review({ recorded_since: '2026-09-30T17:00:00Z' }); // 1 Oct 2026, 01:00 in Singapore
  assert.equal(planXeroSalesExport(events, r, { from: '2026-10-01' }).unrecorded, true);
  assert.equal(planXeroSalesExport(events, r, { from: '2026-09-15' }).unrecorded, true);
  assert.equal(planXeroSalesExport(events, r, { from: '2026-10-02' }).unrecorded, false);
  assert.equal(planXeroSalesExport(events, r, { from: '2026-10-02' }).needsReview, false);
  // Nothing in the file and nothing downloaded before: nothing to confirm.
  const onlyLeftOut = [ev('l', 100, '2026-08-03', { event_kind: 'legacy_refund_left_out', document_number: null })];
  assert.equal(planXeroSalesExport(onlyLeftOut, null, { from: '2026-08-01' }).needsReview, false);
});

test('documents already downloaded unchanged are left out unless asked for again', () => {
  const a = ev('a', '100.00', '2026-08-02'), b = ev('b', 50, '2026-08-03');
  const r = review({ exports: [augExport], downloads: [download(a, { amount: 100 })] });
  const plan = planXeroSalesExport([a, b], r);
  assert.deepEqual(ids(plan.already.map(x => x.event)), ['a'], '100.00 and 100 are the same amount');
  assert.deepEqual(ids(plan.include), ['b']);
  assert.equal(plan.needsReview, true);
  assert.deepEqual(ids(plan.again), [], 'nothing is asked for again');
  const again = planXeroSalesExport([a, b], r, { skipDownloaded: false });
  assert.deepEqual(ids(again.include), ['a', 'b']);
  assert.deepEqual(ids(again.again), ['a'], 'a document asked for again is marked, so the server records it again');
  assert.deepEqual(ids(plan.late), ['b'], 'b is in a downloaded period but was not in the download');
});

test('a downloaded document with another date, amount or number is never put in the file again', () => {
  const base = ev('a', 100, '2026-08-02');
  for (const now of [{ ...base, amount: 90 }, { ...base, document_date: '2026-08-03' }, { ...base, document_number: 'INV-a-PAY-other' }]) {
    const plan = planXeroSalesExport([now], review({ exports: [augExport], downloads: [download(base)] }), { skipDownloaded: false });
    assert.equal(plan.changed.length, 1);
    assert.deepEqual(plan.include, [], 'left out even when asked for the downloaded ones again');
    assert.equal(plan.needsReview, true);
  }
});

test('a document new in a downloaded period is in the file and pointed out; another store\'s is simply new', () => {
  const lateA = ev('late', 70, '2026-08-25'), b = ev('b', 40, '2026-08-25', { store_id: 'store-c' });
  const sep = ev('sep', 10, '2026-09-02');
  const plan = planXeroSalesExport([lateA, b, sep], review({ exports: [augExport] }));
  assert.deepEqual(ids(plan.late), ['late'], 'store C was not covered by the August download');
  assert.deepEqual(ids(plan.include), ['b', 'late', 'sep']);
  assert.equal(plan.needsReview, true);
  // An export for store A alone covers store A alone.
  const one = planXeroSalesExport([lateA, ev('bb', 1, '2026-08-25', { store_id: 'store-b' })],
    review({ exports: [{ ...augExport, store_id: 'store-a', covered_store_ids: ['store-a'] }] }));
  assert.deepEqual(ids(one.late), ['late']);
  // A late document alone makes the person read the review; a new one alone does not.
  const since = review({ exports: [augExport], recorded_since: '2026-07-01T02:00:00Z' });
  assert.equal(planXeroSalesExport([lateA], since, { from: '2026-08-01' }).needsReview, true);
  assert.equal(planXeroSalesExport([b], since, { from: '2026-08-01' }).needsReview, false);
});

test('documents missed from earlier downloads are added unless the person says not to', () => {
  const missed = [ev('m2', 30, '2026-07-20'), ev('m1', 20, '2026-07-10')];
  const plan = planXeroSalesExport([ev('a', 1, '2026-09-01')], review({ missed }));
  assert.deepEqual(ids(plan.missed), ['m1', 'm2']);
  assert.deepEqual(ids(plan.include), ['m1', 'm2', 'a']);
  assert.equal(plan.needsReview, true);
  assert.deepEqual(ids(planXeroSalesExport([ev('a', 1, '2026-09-01')], review({ missed }), { addMissed: false }).include), ['a']);
});

test('vanished documents are shown and make the person read the review', () => {
  const vanished = [{ event_kind: 'receipt', event_id: 'v', document_number: 'INV-v-PAY-v', document_date: '2026-08-26', amount: 100,
    exported_at: '2026-09-01T02:00:00Z', now_date: null, now_amount: null, moved: false }];
  const plan = planXeroSalesExport([], review({ vanished }));
  assert.deepEqual(plan.vanished, vanished);
  assert.deepEqual(plan.moved, []);
  assert.equal(plan.needsReview, true);
  assert.deepEqual(plan.include, []);
});

test('a downloaded document now on another store\'s invoice is shown as moved, not as vanished', () => {
  const moved = { event_kind: 'receipt', event_id: 'm', document_number: 'INV-m-PAY-m', document_date: '2026-08-26', amount: 100,
    exported_at: '2026-09-01T02:00:00Z', now_date: '2026-08-26', now_amount: 100, moved: true, now_store_id: 'store-b' };
  const gone = { ...moved, event_id: 'g', document_number: 'INV-g-PAY-g', now_date: null, now_amount: null, moved: false, now_store_id: null };
  const plan = planXeroSalesExport([], review({ vanished: [moved, gone] }), { from: '2026-08-01' });
  assert.deepEqual(ids(plan.moved), ['m']);
  assert.deepEqual(ids(plan.vanished), ['g']);
  assert.equal(planXeroSalesExport([], review({ vanished: [moved] })).needsReview, true);
  assert.deepEqual(plan.include, []);
});

test('the overlapping downloads and the first recorded download are passed on', () => {
  const plan = planXeroSalesExport([], review({ exports: [augExport] }));
  assert.deepEqual(plan.exports, [augExport]);
  assert.equal(plan.recordedSince, '2026-09-01T02:00:00Z');
  assert.equal(plan.needsReview, false, 'an overlapping download alone, with nothing in it now, needs no reading');
});

test('numbers, amounts and labels', () => {
  assert.deepEqual(EXPORTABLE_KINDS, ['receipt', 'correction_replacement', 'correction_reversal', 'refund']);
  const id = '0f1e2d3c-4b5a-6978-8796-a5b4c3d2e1f0';
  assert.equal(expectedDocumentNumber({ event_kind: 'receipt', event_id: id, invoice_no: 'INV-2026-0001' }), 'INV-2026-0001-PAY-0f1e2d3c4b5a69788796a5b4c3d2e1f0');
  assert.equal(expectedDocumentNumber({ event_kind: 'correction_replacement', event_id: id, invoice_no: 'I' }), `I-ADJ-${id.replace(/-/g, '')}`);
  assert.equal(expectedDocumentNumber({ event_kind: 'correction_reversal', event_id: id, invoice_no: 'I' }), `I-REV-${id.replace(/-/g, '')}`);
  assert.equal(expectedDocumentNumber({ event_kind: 'refund', event_id: id, invoice_no: 'I' }), `I-REF-${id.replace(/-/g, '')}`);
  assert.equal(expectedDocumentNumber({ event_kind: 'legacy_refund_left_out', event_id: id, invoice_no: 'I' }), null);
  assert.equal(expectedDocumentNumber({ event_kind: 'refund_unsourced', event_id: id, invoice_no: 'I' }), null);
  assert.equal(eventKey({ event_kind: 'refund', event_id: 'x' }), 'refund:x');
  assert.equal(amountCents('100'), 10000n);
  assert.equal(amountCents(100.5), 10050n);
  assert.equal(amountCents('-0.01'), -1n);
  assert.throws(() => amountCents('1.234'), /invalid currency amount/);
  assert.throws(() => amountCents(null), /invalid currency amount/);
  assert.equal(formatCents(-2600n), '-26.00');
  assert.equal(sgd(-2600n), '-S$26.00');
  assert.equal(sgd(5n), 'S$0.05');
  assert.equal(totalCents([{ amount: '1.10' }, { amount: -0.1 }]), 100n);
  assert.equal(dayLabel('2026-08-05'), '5 Aug 2026');
  assert.equal(momentLabel('2026-09-30T17:05:00Z'), '1 Oct 2026, 01:05', 'Singapore time');
  assert.equal(singaporeDay('2026-09-30T15:59:00Z'), '2026-09-30');
  assert.equal(singaporeDay('2026-09-30T16:00:00Z'), '2026-10-01');
  assert.equal(singaporeDay(null), null);
  assert.equal(singaporeDay('not a time'), null);
});
