import React, { useEffect, useMemo, useRef, useState } from 'react';
import { AlertTriangle, FileSpreadsheet } from 'lucide-react';
import { XERO_SALES_INVOICE_HEADERS, toXeroCsv, findMissingMandatory, xeroCsvFilename } from '../lib/xero/salesInvoiceTemplate.mjs';
import {
  type XeroSalesEvent, type XeroSalesPlan, type XeroSalesReview,
  amountCents, dayLabel, eventKey, expectedDocumentNumber, formatCents, momentLabel, planXeroSalesExport, sgd, totalCents,
} from '../lib/xero/salesExport.mjs';
import { supabase } from '../lib/supabase';
import { singaporeToday } from '../lib/invoices/business';
import { Modal } from './ui';

type SalesExportData = { events: XeroSalesEvent[]; review: XeroSalesReview };

const fetchAll = async <T,>(build: (offset: number, limit: number) => any): Promise<T[]> => {
  const pageSize = 1000;
  const rows: T[] = [];
  for (let offset = 0; ; offset += pageSize) {
    const { data, error } = await build(offset, pageSize);
    if (error) throw new Error(error.message);
    const page = (data as T[]) ?? [];
    rows.push(...page);
    if (page.length < pageSize) return rows;
  }
};

/**
 * The export's documents between two days (xero_sales_events, 411) and what
 * was downloaded before for the same days and store (xero_sales_export_review).
 * The server gives each document its contact, so a deleted customer no longer
 * stops the export.
 */
export async function loadXeroSalesExport(db: typeof supabase, from: string, to: string, storeId = ''): Promise<SalesExportData> {
  const args = { p_from: from, p_to: to, p_store_id: storeId || null };
  const events = await fetchAll<XeroSalesEvent>((offset, limit) => db.rpc('xero_sales_events', args)
    .order('document_date').order('event_id').order('event_kind')
    .range(offset, offset + limit - 1));
  const { data, error } = await db.rpc('xero_sales_export_review', args);
  if (error) throw new Error(error.message);
  return { events, review: data as XeroSalesReview };
}

export function xeroSalesDate(day: string): string {
  const parsed = new Date(`${day}T00:00:00Z`);
  if (!/^\d{4}-\d{2}-\d{2}$/.test(day) || !Number.isFinite(parsed.getTime()) || parsed.toISOString().slice(0, 10) !== day) {
    throw new Error('A sales event needs a valid payment or refund date before export.');
  }
  return day.split('-').reverse().join('/');
}

/**
 * One stable draft document per money event: a payment on the day it was
 * received, a correction on the day it was made, a refund (also on a
 * cancellation) as a credit note on the day it was recorded. Original
 * invoice identifiers stay in Reference and Description. Historical payments
 * are not given fabricated product allocations or product SKUs.
 *
 * Xero uses the same 29-column template for draft customer credit notes:
 * negative UnitAmount and a distinct credit-note number identify reductions.
 * https://central.xero.com/0/article/Import-a-customer-credit-note-AU
 */
export function buildXeroSalesRows(events: XeroSalesEvent[], accountCode: string, taxType: string) {
  const seen = new Set<string>();
  const rows: Record<string, unknown>[] = [];
  let total = 0n;
  for (const event of events) {
    if (event.event_kind === 'refund_unsourced') {
      throw new Error(`A refund on invoice ${event.invoice_no ?? '(unknown)'} on ${dayLabel(event.document_date)} was recorded without the payment it returned, so it cannot be told whether money went back. Review it before exporting these dates.`);
    }
    if (!event.invoice_no || !event.event_id) throw new Error('A sales event is missing its original invoice or event reference.');
    const prefix = expectedDocumentNumber(event);
    if (!prefix) throw new Error(`A sales event on invoice ${event.invoice_no} is of a kind the export does not know. Review it before exporting.`);
    // The number must be the one the page has always written, so a document
    // downloaded before keeps its number in Xero.
    if (event.document_number !== prefix) throw new Error(`The Xero number for invoice ${event.invoice_no} is not the expected one. Reload before exporting.`);
    const key = eventKey(event);
    if (seen.has(key)) throw new Error('The sales export returned a duplicate event. Reload before exporting.');
    seen.add(key);
    const cents = amountCents(event.amount);
    if (cents === 0n) continue; // Nothing came in or went back.
    const reduction = event.event_kind === 'refund' || event.event_kind === 'correction_reversal';
    if (reduction ? cents > 0n : cents < 0n) {
      throw new Error('A sales event has an inconsistent payment or refund amount. Review it before exporting.');
    }
    if (event.customer_id && event.contact_name == null) {
      throw new Error(`The customer for invoice ${event.invoice_no} could not be found. Reload before exporting.`);
    }
    const date = xeroSalesDate(event.document_date);
    const description = {
      receipt: 'Received payment', correction_replacement: 'Corrected received payment',
      correction_reversal: 'Payment correction reversal', refund: 'Refund',
    }[event.event_kind as 'receipt'];
    rows.push({
      '*ContactName': event.customer_id ? event.contact_name : 'Walk-in customer',
      EmailAddress: event.contact_email ?? '', POAddressLine1: event.contact_address ?? '',
      '*InvoiceNumber': event.document_number,
      Reference: event.invoice_no, '*InvoiceDate': date, '*DueDate': date,
      InventoryItemCode: '',
      '*Description': `${description} for invoice ${event.invoice_no}. ENERGIA invoice ID: ${event.invoice_id}; event: ${event.event_id}.`,
      '*Quantity': 1, '*UnitAmount': formatCents(cents),
      '*AccountCode': accountCode.trim(), '*TaxType': taxType.trim(), TaxAmount: 0, Currency: 'SGD',
    });
    total += cents;
  }
  const missing = findMissingMandatory(rows);
  if (missing.length) throw new Error(`Row ${missing[0].row} has no ${missing[0].field}. Complete the required details before exporting.`);
  return { rows, total: formatCents(total) };
}

/** An error the database answered (a SQLSTATE): it ran and rolled back, so nothing was recorded. */
export class XeroRecordRefused extends Error {}

/**
 * Records what a download holds (record_xero_sales_export, 411), before the
 * file is handed over. Documents already downloaded that the person asked for
 * again (`again`, by eventKey) are marked "redownload"; the server refuses any
 * other document an earlier download holds.
 */
export async function recordXeroSalesDownload(db: typeof supabase, from: string, to: string, storeId: string,
  events: XeroSalesEvent[], requestId: string, again: ReadonlySet<string> = new Set()) {
  const { data, error } = await db.rpc('record_xero_sales_export', {
    p_from: from, p_to: to, p_store_id: storeId || null, p_request_id: requestId,
    p_documents: events.map(e => ({
      event_kind: e.event_kind, event_id: e.event_id, document_number: e.document_number,
      document_date: e.document_date, amount: e.amount, ...(again.has(eventKey(e)) ? { redownload: true } : {}),
    })),
  });
  if (error) {
    // No SQLSTATE (the connection failed, or a gateway answered): the record
    // may have been made, so the caller retries the same request.
    throw /^[0-9A-Z]{5}$/.test(String((error as { code?: unknown }).code ?? ''))
      ? new XeroRecordRefused(error.message) : new Error(error.message);
  }
  return data as { export_id: string; exported_at: string; document_count: number; net_total: number | string };
}

const plural = (n: number, one: string, many = `${one}s`) => `${n} ${n === 1 ? one : many}`;
const listed = (items: string[], max = 4) =>
  items.slice(0, max).join('; ') + (items.length > max ? `; and ${items.length - max} more` : '');
const docLabel = (number: string | null, date: string, amount: number | string) =>
  `${number} (${dayLabel(date)}, ${sgd(amountCents(amount))})`;

export const XeroExportButton: React.FC<{
  stores: { id: string; name: string }[]; defaultStoreId?: string;
}> = ({ stores, defaultStoreId = '' }) => {
  const [open, setOpen] = useState(false);
  const [from, setFrom] = useState('');
  const [to, setTo] = useState('');
  const [storeId, setStoreId] = useState(defaultStoreId);
  const [accountCode, setAccountCode] = useState('1011');
  const [taxType, setTaxType] = useState('No Tax (0%)');
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [note, setNote] = useState<string | null>(null);
  // What was loaded for the dates and store shown, waiting for the person to
  // read the review and download.
  const [loaded, setLoaded] = useState<(SalesExportData & { key: string; from: string }) | null>(null);
  const [skipDownloaded, setSkipDownloaded] = useState(true);
  const [addMissed, setAddMissed] = useState(true);
  // Dates from before the first recorded download: the person confirms they
  // checked Xero for documents the old export put there.
  const [checkedOld, setCheckedOld] = useState(false);
  // One export at a time: a second click while the first is building is ignored.
  const running = useRef(false);
  // A download whose record was sent but not answered is retried with the same
  // request ID, so it is recorded once.
  const pending = useRef<{ signature: string; id: string } | null>(null);
  // A download (without a review) whose record got no answer: the next click
  // sends the same documents again rather than reading the dates again, so a
  // record made but not answered is replayed and its file handed over.
  const retry = useRef<{ key: string; plan: XeroSalesPlan } | null>(null);
  const scopeKey = `${from}|${to}|${storeId}`;

  // Another date or store makes the review stale.
  useEffect(() => {
    setLoaded(prev => (prev && prev.key !== scopeKey ? null : prev));
    if (retry.current && retry.current.key !== scopeKey) retry.current = null;
  }, [scopeKey]);

  const plan: XeroSalesPlan | null = useMemo(
    () => (loaded ? planXeroSalesExport(loaded.events, loaded.review, { skipDownloaded, addMissed, from: loaded.from }) : null),
    [loaded, skipDownloaded, addMissed]);

  const storeName = (id: string | null) => (id ? (stores.find(s => s.id === id)?.name ?? 'one store') : 'all stores');

  const download = async (current: XeroSalesPlan, key: string) => {
    const { rows, total } = buildXeroSalesRows(current.include, accountCode, taxType);
    const legacy = current.legacy.length
      ? ` Left out: ${plural(current.legacy.length, 'payment')} (${sgd(totalCents(current.legacy))}) on ${[...new Set(current.legacy.map(e => e.invoice_no))].join(', ')}, refunded before refunds were recorded.`
      : '';
    if (!rows.length) { setErr(`No payments, corrections or refunds to export between these dates.${legacy}`); return; }
    const exported = current.include.filter(e => amountCents(e.amount) !== 0n);
    const again = new Set(current.again.map(eventKey));
    // Recorded first: the record is exactly what the file holds, and a file is
    // never handed over that the next export would not know about.
    const signature = JSON.stringify([from, to, storeId,
      exported.map(e => [eventKey(e), e.document_date, String(e.amount), again.has(eventKey(e))])]);
    if (pending.current?.signature !== signature) pending.current = { signature, id: crypto.randomUUID() };
    let record;
    try {
      record = await recordXeroSalesDownload(supabase, from, to, storeId, exported, pending.current.id, again);
    } catch (error) {
      if (error instanceof XeroRecordRefused) {
        // Refused, so nothing was recorded: the next click reads the dates
        // again (the server's message says what changed).
        pending.current = null; retry.current = null; setLoaded(null);
      } else retry.current = { key, plan: current };
      throw error;
    }
    pending.current = null; retry.current = null;
    const scope = storeId ? (stores.find(s => s.id === storeId)?.name ?? 'store') : 'all-stores';
    const blob = new Blob([toXeroCsv(rows, XERO_SALES_INVOICE_HEADERS)], { type: 'text/csv;charset=utf-8' });
    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.href = url; link.download = xeroCsvFilename(scope, from, to);
    document.body.appendChild(link); link.click(); link.remove(); URL.revokeObjectURL(url);
    const reductions = rows.filter(row => String(row['*UnitAmount']).startsWith('-')).length;
    const history = current.exports.length ? '' : (current.recordedSince
      ? ` No earlier download of these dates is recorded since ${momentLabel(current.recordedSince)}; downloads before that were not recorded.`
      : ' This is the first download the app has recorded; downloads made before this version were not recorded, so check Xero for documents already imported.');
    setNote(`Downloaded ${plural(rows.length, 'document')}, including ${plural(reductions, 'credit note')}. Net: S$${total}. `
      + `Recorded as downloaded at ${momentLabel(record?.exported_at)}.${legacy}${history} Review the drafts in Xero before approving them.`);
    setLoaded(null);
  };

  const run = async () => {
    if (running.current) return;
    if (!from || !to) { setErr('Choose both a start and an end date.'); return; }
    if (to < from) { setErr('The end date cannot be before the start date.'); return; }
    if (!accountCode.trim() || !taxType.trim()) { setErr('Enter the Xero account code and tax rate.'); return; }
    running.current = true;
    setBusy(true); setErr(null); setNote(null);
    try {
      if (loaded && plan && loaded.key === scopeKey) {
        if (plan.unrecorded && !checkedOld) { setErr('Tick that you have checked Xero for these dates first.'); return; }
        await download(plan, scopeKey);
        return;
      }
      if (retry.current?.key === scopeKey) {
        await download(retry.current.plan, scopeKey);
        return;
      }
      const data = await loadXeroSalesExport(supabase, from, to, storeId);
      // Every document between the dates is checked before the person is asked
      // anything, or anything is recorded or downloaded: one that cannot be
      // exported stops these dates.
      buildXeroSalesRows(data.events.filter(e => e.event_kind !== 'legacy_refund_left_out'), accountCode, taxType);
      const fresh = planXeroSalesExport(data.events, data.review, { skipDownloaded: true, addMissed: true, from });
      if (fresh.needsReview) {
        setSkipDownloaded(true); setAddMissed(true); setCheckedOld(false);
        setLoaded({ ...data, key: scopeKey, from });
        return;
      }
      await download(fresh, scopeKey);
    } catch (error: any) { setErr(error.message || 'Unable to prepare the complete sales export.'); }
    finally { setBusy(false); running.current = false; }
  };

  const openDialog = () => {
    const today = singaporeToday();
    setFrom(`${today.slice(0, 7)}-01`); setTo(today);
    setStoreId(defaultStoreId); setErr(null); setNote(null); setLoaded(null); setOpen(true);
  };

  const reviewing = !!(loaded && plan && loaded.key === scopeKey);
  const includeCount = plan ? plan.include.filter(e => amountCents(e.amount) !== 0n).length : 0;
  const downloadedBefore = !!plan && (plan.exports.length + plan.already.length + plan.changed.length + plan.late.length
    + plan.missed.length + plan.vanished.length + plan.moved.length > 0);

  return <>
    <button className="btn btn-secondary" onClick={openDialog}><FileSpreadsheet size={15} /> Xero Export</button>
    {open && <Modal title="Export sales for Xero" maxWidth={600} onClose={() => { if (!busy) setOpen(false); }}
      footer={<>
        <button className="btn btn-secondary" disabled={busy} onClick={() => setOpen(false)}>Close</button>
        <button className="btn btn-primary" onClick={() => void run()}
          disabled={busy || (reviewing && (includeCount === 0 || (!!plan?.unrecorded && !checkedOld)))}>
          {busy ? 'Building…' : reviewing ? `Download ${plural(includeCount, 'document')}` : 'Export CSV'}
        </button>
      </>}>
      <div className="form-grid" data-testid="xero-sales">
        <div style={{ fontSize: 12.5, color: 'var(--text-secondary)' }} data-testid="xero-sales-rules">
          Every payment is exported on the day it was received, even if the invoice is cancelled or refunded later.
          Refunds, including those made when an invoice is cancelled, are credit notes on the day the refund is recorded
          in the app, and a payment correction is dated the day it was made. So dates you have downloaded do not change afterwards.
          A cancellation alone returns no money: what is still held stays as received until its refund is recorded.
          Payments with wallet credit are left out (no new money came in). These totals can differ from the Sales report,
          which leaves cancelled and refunded invoices out.
        </div>
        <div className="form-grid-2">
          <div className="form-group" style={{ marginBottom: 0 }}>
            <label htmlFor="xero-sales-from">From *</label>
            <input id="xero-sales-from" type="date" value={from} disabled={busy} onChange={e => setFrom(e.target.value)} />
          </div>
          <div className="form-group" style={{ marginBottom: 0 }}>
            <label htmlFor="xero-sales-to">To *</label>
            <input id="xero-sales-to" type="date" value={to} min={from} disabled={busy} onChange={e => setTo(e.target.value)} />
          </div>
        </div>
        <div className="form-grid-2">
          <div className="form-group" style={{ marginBottom: 0 }}>
            <label htmlFor="xero-sales-store">Store</label>
            <select id="xero-sales-store" value={storeId} disabled={busy} onChange={e => setStoreId(e.target.value)}>
              <option value="">All stores</option>{stores.map(s => <option key={s.id} value={s.id}>{s.name}</option>)}
            </select>
          </div>
          <div className="form-group" style={{ marginBottom: 0 }}>
            <label htmlFor="xero-sales-code">Xero account code</label>
            <input id="xero-sales-code" value={accountCode} disabled={busy} onChange={e => setAccountCode(e.target.value)} placeholder="1011" />
            <div style={{ fontSize: 11, color: 'var(--text-muted)', marginTop: 3 }}>Sales account in your Xero chart of accounts.</div>
          </div>
          <div className="form-group" style={{ marginBottom: 0 }}>
            <label htmlFor="xero-sales-tax">Xero tax rate</label>
            <input id="xero-sales-tax" value={taxType} disabled={busy} onChange={e => setTaxType(e.target.value)} placeholder="No Tax (0%)" />
            <div style={{ fontSize: 11, color: 'var(--text-muted)', marginTop: 3 }}>Use your Xero zero-tax rate name or <code>NONE</code>.</div>
          </div>
        </div>
        {reviewing && plan && (
          <div className="alert alert-warning" data-testid="xero-sales-review" style={{ marginBottom: 0 }}>
            <AlertTriangle size={15} />
            <div>
              {plan.unrecorded && <div data-testid="xero-sales-unrecorded" style={{ marginBottom: downloadedBefore ? 8 : 0 }}>
                <div style={{ fontWeight: 600, marginBottom: 4 }}>Check Xero first: earlier downloads of these dates may not be recorded</div>
                <div>
                  {plan.recordedSince
                    ? `Downloads before ${momentLabel(plan.recordedSince)} were not recorded, and these dates start on or before that day.`
                    : 'No download is recorded yet: downloads made before this version of the app were not recorded.'}
                  {' '}If any of these dates were imported into Xero with the old export, those documents are in Xero already
                  with the same numbers, and importing them again would duplicate them.
                </div>
                <label style={{ display: 'flex', gap: 6, alignItems: 'flex-start', marginTop: 6, fontWeight: 400 }}>
                  <input id="xero-sales-checked-old" type="checkbox" checked={checkedOld} disabled={busy} onChange={e => setCheckedOld(e.target.checked)} />
                  <span>I have checked Xero for these dates and will not import a document that is already there.</span>
                </label>
              </div>}
              {downloadedBefore && <div style={{ fontWeight: 600, marginBottom: 4 }}>Some of these dates were downloaded before</div>}
              <ul style={{ margin: 0, paddingLeft: 18 }}>
                {plan.exports.slice(0, 3).map(x => (
                  <li key={x.id}>Downloaded {momentLabel(x.exported_at)} by {x.exported_by}: {dayLabel(x.from_date)} – {dayLabel(x.to_date)}, {storeName(x.store_id)} ({plural(x.document_count, 'document')} of the stores chosen here).</li>
                ))}
                {plan.exports.length > 3 && <li>and {plural(plan.exports.length - 3, 'earlier download')}.</li>}
                {plan.late.length > 0 && <li data-testid="xero-sales-late">
                  {plural(plan.late.length, 'document')} {plan.late.length === 1 ? 'is' : 'are'} new in dates already downloaded (entered afterwards, so not in Xero yet) and {plan.late.length === 1 ? 'is' : 'are'} in this file: {listed(plan.late.map(e => docLabel(e.document_number, e.document_date, e.amount)))}.
                </li>}
                {plan.changed.length > 0 && <li data-testid="xero-sales-changed">
                  {plural(plan.changed.length, 'downloaded document')} now {plan.changed.length === 1 ? 'has' : 'have'} another date or amount and {plan.changed.length === 1 ? 'is' : 'are'} left out of this file. Correct {plan.changed.length === 1 ? 'it' : 'them'} in Xero by hand: {listed(plan.changed.map(c => `${c.download.document_number}: ${sgd(amountCents(c.download.amount))} on ${dayLabel(c.download.document_date)} then, ${sgd(amountCents(c.event.amount))} on ${dayLabel(c.event.document_date)} now`))}.
                </li>}
                {plan.vanished.length > 0 && <li data-testid="xero-sales-vanished">
                  {plural(plan.vanished.length, 'downloaded document')} {plan.vanished.length === 1 ? 'is' : 'are'} no longer listed for these dates (its invoice was deleted, or it is dated another day now). Check {plan.vanished.length === 1 ? 'it' : 'them'} in Xero: {listed(plan.vanished.map(v => `${docLabel(v.document_number, v.document_date, v.amount)}${v.now_date ? `, now ${dayLabel(v.now_date)}` : ', gone'}`))}.
                </li>}
                {plan.moved.length > 0 && <li data-testid="xero-sales-moved">
                  {plural(plan.moved.length, 'downloaded document')} {plan.moved.length === 1 ? 'is' : 'are'} now on {plan.moved.length === 1 ? 'an invoice' : 'invoices'} of another store (moved after the download). {plan.moved.length === 1 ? 'It is' : 'They are'} in Xero already, so nothing needs doing and {plan.moved.length === 1 ? 'it is' : 'they are'} not downloaded again for that store: {listed(plan.moved.map(v => `${docLabel(v.document_number, v.document_date, v.amount)}, now ${v.now_store_id ? storeName(v.now_store_id) : 'another store'}`))}.
                </li>}
              </ul>
              {plan.already.length > 0 && <label style={{ display: 'flex', gap: 6, alignItems: 'flex-start', marginTop: 6, fontWeight: 400 }}>
                <input id="xero-sales-skip" type="checkbox" checked={skipDownloaded} disabled={busy} onChange={e => setSkipDownloaded(e.target.checked)} />
                <span>Leave out the {plural(plan.already.length, 'document')} already downloaded ({sgd(totalCents(plan.already.map(a => a.event)))}). Importing them again would duplicate them in Xero; untick only to download them again on purpose.</span>
              </label>}
              {plan.missed.length > 0 && <label style={{ display: 'flex', gap: 6, alignItems: 'flex-start', marginTop: 6, fontWeight: 400 }}>
                <input id="xero-sales-missed" type="checkbox" checked={addMissed} disabled={busy} onChange={e => setAddMissed(e.target.checked)} />
                <span>Add {plural(plan.missed.length, 'document')} dated outside these dates, entered after {plan.missed.length === 1 ? 'its' : 'their'} own dates were downloaded (not in Xero yet): {listed(plan.missed.map(e => docLabel(e.document_number, e.document_date, e.amount)))}.</span>
              </label>}
              {includeCount === 0 && <div style={{ marginTop: 6 }} data-testid="xero-sales-nothing">
                Nothing to download with these choices: everything between these dates was already downloaded.
              </div>}
            </div>
          </div>
        )}
        {err && <div className="alert alert-danger" role="alert" style={{ marginBottom: 0 }}><span>⚠</span><div>{err}</div></div>}
        {note && <div className="alert alert-info" role="status" style={{ marginBottom: 0 }}><div>{note}</div></div>}
        <div style={{ fontSize: 11.5, color: 'var(--text-muted)' }}>
          One draft document per payment, correction or refund, with the original invoice number as its Reference.
          Negative amounts import as credit notes. Each download is recorded, so the next export says what was already
          downloaded or entered late; downloads made before this version were not recorded, so check Xero for those.
          Product item codes are omitted.
        </div>
      </div>
    </Modal>}
  </>;
};
