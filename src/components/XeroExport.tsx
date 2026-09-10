import React, { useState } from 'react';
import { FileSpreadsheet } from 'lucide-react';
import { XERO_SALES_INVOICE_HEADERS, toXeroCsv, findMissingMandatory, xeroCsvFilename } from '../lib/xero/salesInvoiceTemplate.mjs';
import { supabase } from '../lib/supabase';
import { singaporeToday } from '../lib/invoices/business';
import { Modal } from './ui';

type SalesEvent = {
  invoice_id: string; event_id: string; sales_date: string; amount: string | number;
  event_kind: 'receipt' | 'correction_replacement' | 'correction_reversal' | 'refund';
};
type ExportInvoice = { id: string; invoice_no: string; customer_id: string | null; store_id: string };
type ExportCustomer = { id: string; full_name: string; email?: string | null; address?: string | null };
type SalesExportData = { events: SalesEvent[]; invoices: ExportInvoice[]; customers: ExportCustomer[] };

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

/** Read the same dated, store-scoped external-money events used by Sales reports. */
export async function loadXeroSalesEvents(db: typeof supabase, from: string, to: string, storeId = ''): Promise<SalesExportData> {
  const events = await fetchAll<SalesEvent>((offset, limit) => db.rpc('invoice_sales_ledger')
    .gte('sales_date', from).lte('sales_date', to)
    .order('sales_date').order('event_id').order('event_kind').order('invoice_id')
    .range(offset, offset + limit - 1));
  const fetchByIds = async <T,>(table: string, columns: string, ids: string[]): Promise<T[]> => {
    const uniqueIds = [...new Set(ids)].sort();
    const rows: T[] = [];
    for (let i = 0; i < uniqueIds.length; i += 200) {
      const chunk = uniqueIds.slice(i, i + 200);
      rows.push(...await fetchAll<T>((offset, limit) => db.from(table).select(columns)
        .in('id', chunk).order('id').range(offset, offset + limit - 1)));
    }
    return rows;
  };
  // A refund in this period can belong to an older or cancelled invoice.
  // Do not apply invoice status/date filters or substitute invoice.paid_amount.
  const invoices = await fetchByIds<ExportInvoice>('invoices', 'id,invoice_no,customer_id,store_id', events.map(e => e.invoice_id));
  const invoiceMap = new Map(invoices.map(i => [i.id, i]));
  if (events.some(e => !invoiceMap.has(e.invoice_id))) {
    throw new Error('An invoice referenced by the sales report could not be loaded. Reload before exporting.');
  }
  const scopedInvoices = storeId ? invoices.filter(i => i.store_id === storeId) : invoices;
  const scopedIds = new Set(scopedInvoices.map(i => i.id));
  const customers = await fetchByIds<ExportCustomer>('customers', 'id,full_name,email,address',
    scopedInvoices.map(i => i.customer_id).filter((id): id is string => !!id));
  return { events: events.filter(e => scopedIds.has(e.invoice_id)), invoices: scopedInvoices, customers };
}

// Decimal cents keep the CSV total exact. One unit per event avoids prorating.
const amountCents = (amount: string | number): bigint => {
  const match = /^(-?)(\d+)(?:\.(\d{1,2}))?$/.exec(String(amount));
  if (!match) throw new Error('A sales event has an invalid currency amount. Review it before exporting.');
  const cents = BigInt(match[2]) * 100n + BigInt((match[3] ?? '').padEnd(2, '0'));
  return match[1] ? -cents : cents;
};
const formatCents = (cents: bigint) => {
  const absolute = cents < 0n ? -cents : cents;
  return `${cents < 0n ? '-' : ''}${absolute / 100n}.${String(absolute % 100n).padStart(2, '0')}`;
};
export function xeroSalesDate(day: string): string {
  const parsed = new Date(`${day}T00:00:00Z`);
  if (!/^\d{4}-\d{2}-\d{2}$/.test(day) || !Number.isFinite(parsed.getTime()) || parsed.toISOString().slice(0, 10) !== day) {
    throw new Error('A sales event needs a valid business or refund date before export.');
  }
  return day.split('-').reverse().join('/');
}

/**
 * Recognized-sales export, not a second copy of the full billing document.
 * One stable document per external receipt/refund keeps partial payments,
 * corrections, overpayments and refund-only periods equal to the sales ledger.
 * Original invoice identifiers stay in Reference and Description. Historical
 * payments are not assigned fabricated product allocations or product SKUs.
 *
 * Xero uses the same 29-column template for draft customer credit notes:
 * negative UnitAmount and a distinct credit-note number identify reductions.
 * https://central.xero.com/0/article/Import-a-customer-credit-note-AU
 */
export function buildXeroSalesRows(data: SalesExportData, accountCode: string, taxType: string) {
  const invoices = new Map(data.invoices.map(i => [i.id, i]));
  const customers = new Map(data.customers.map(c => [c.id, c]));
  const seen = new Set<string>();
  const rows: Record<string, unknown>[] = [];
  let totalCents = 0n;
  for (const event of data.events) {
    const invoice = invoices.get(event.invoice_id);
    if (!invoice?.invoice_no || !event.event_id) throw new Error('A sales event is missing its original invoice or event reference.');
    const key = `${event.invoice_id}:${event.event_kind}:${event.event_id}`;
    if (seen.has(key)) throw new Error('The sales report returned a duplicate event. Reload before exporting.');
    seen.add(key);
    const cents = amountCents(event.amount);
    if (cents === 0n) continue; // Wallet-only refunds contribute zero external sales.
    const reduction = event.event_kind === 'refund' || event.event_kind === 'correction_reversal';
    if (!['receipt', 'correction_replacement', 'correction_reversal', 'refund'].includes(event.event_kind)
      || (reduction ? cents > 0n : cents < 0n)) {
      throw new Error('A sales event has an inconsistent payment or refund amount. Review it before exporting.');
    }
    const customer = invoice.customer_id ? customers.get(invoice.customer_id) : null;
    if (invoice.customer_id && !customer) throw new Error(`The customer for invoice ${invoice.invoice_no} could not be loaded. Reload before exporting.`);
    const date = xeroSalesDate(event.sales_date);
    const prefix = { receipt: 'PAY', correction_replacement: 'ADJ', correction_reversal: 'REV', refund: 'REF' }[event.event_kind];
    const description = {
      receipt: 'Received payment', correction_replacement: 'Corrected received payment',
      correction_reversal: 'Payment correction reversal', refund: 'Refund',
    }[event.event_kind];
    rows.push({
      '*ContactName': customer ? customer.full_name : 'Walk-in customer',
      EmailAddress: customer?.email ?? '', POAddressLine1: customer?.address ?? '',
      '*InvoiceNumber': `${invoice.invoice_no}-${prefix}-${event.event_id.replace(/-/g, '')}`,
      Reference: invoice.invoice_no, '*InvoiceDate': date, '*DueDate': date,
      InventoryItemCode: '',
      '*Description': `${description} for invoice ${invoice.invoice_no}. ENERGIA invoice ID: ${invoice.id}; event: ${event.event_id}.`,
      '*Quantity': 1, '*UnitAmount': formatCents(cents),
      '*AccountCode': accountCode.trim(), '*TaxType': taxType.trim(), TaxAmount: 0, Currency: 'SGD',
    });
    totalCents += cents;
  }
  const missing = findMissingMandatory(rows);
  if (missing.length) throw new Error(`Row ${missing[0].row} has no ${missing[0].field}. Complete the required details before exporting.`);
  return { rows, total: formatCents(totalCents) };
}

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
  const run = async () => {
    if (!from || !to) { setErr('Choose both a start and an end date.'); return; }
    if (to < from) { setErr('The end date cannot be before the start date.'); return; }
    if (!accountCode.trim() || !taxType.trim()) { setErr('Enter the Xero account code and tax rate.'); return; }
    setBusy(true); setErr(null); setNote(null);
    try {
      const data = await loadXeroSalesEvents(supabase, from, to, storeId);
      const { rows, total } = buildXeroSalesRows(data, accountCode, taxType);
      if (!rows.length) { setErr('No external payment or refund events in that range.'); return; }
      const scope = storeId ? (stores.find(s => s.id === storeId)?.name ?? 'store') : 'all-stores';
      const blob = new Blob([toXeroCsv(rows, XERO_SALES_INVOICE_HEADERS)], { type: 'text/csv;charset=utf-8' });
      const url = URL.createObjectURL(blob);
      const link = document.createElement('a');
      link.href = url; link.download = xeroCsvFilename(scope, from, to);
      document.body.appendChild(link); link.click(); link.remove(); URL.revokeObjectURL(url);
      const reductions = rows.filter(row => String(row['*UnitAmount']).startsWith('-')).length;
      setNote(`Downloaded ${rows.length} event(s), including ${reductions} credit note(s). Net recognized sales: S$${total}. Review the drafts in Xero before approving them.`);
    } catch (error: any) { setErr(error.message || 'Unable to prepare the complete sales export.'); }
    finally { setBusy(false); }
  };
  const openDialog = () => {
    const today = singaporeToday();
    setFrom(`${today.slice(0, 7)}-01`); setTo(today);
    setStoreId(defaultStoreId); setErr(null); setNote(null); setOpen(true);
  };
  return <>
    <button className="btn btn-secondary" onClick={openDialog}><FileSpreadsheet size={15} /> Xero Export</button>
    {open && <Modal title="Export recognized sales for Xero" maxWidth={560} onClose={() => { if (!busy) setOpen(false); }}
      footer={<>
        <button className="btn btn-secondary" disabled={busy} onClick={() => setOpen(false)}>Close</button>
        <button className="btn btn-primary" onClick={run} disabled={busy}>{busy ? 'Building…' : 'Export CSV'}</button>
      </>}>
      <div className="form-grid">
        <div style={{ fontSize: 12.5, color: 'var(--text-secondary)' }}>
          Export external payments on the invoice business date and refunds on the date returned.
          Wallet credit is excluded. Money still held on cancelled invoices remains included.
        </div>
        {err && <div className="alert alert-danger" style={{ marginBottom: 0 }}><span>⚠</span><div>{err}</div></div>}
        {note && <div className="alert alert-info" style={{ marginBottom: 0 }}><div>{note}</div></div>}
        <div className="form-grid-2">
          <div className="form-group" style={{ marginBottom: 0 }}>
            <label>From *</label><input type="date" value={from} disabled={busy} onChange={e => setFrom(e.target.value)} />
          </div>
          <div className="form-group" style={{ marginBottom: 0 }}>
            <label>To *</label><input type="date" value={to} min={from} disabled={busy} onChange={e => setTo(e.target.value)} />
          </div>
        </div>
        <div className="form-grid-2">
          <div className="form-group" style={{ marginBottom: 0 }}>
            <label>Store</label><select value={storeId} disabled={busy} onChange={e => setStoreId(e.target.value)}>
              <option value="">All stores</option>{stores.map(s => <option key={s.id} value={s.id}>{s.name}</option>)}
            </select>
          </div>
          <div className="form-group" style={{ marginBottom: 0 }}>
            <label>Xero account code</label><input value={accountCode} disabled={busy} onChange={e => setAccountCode(e.target.value)} placeholder="1011" />
            <div style={{ fontSize: 11, color: 'var(--text-muted)', marginTop: 3 }}>Sales account in your Xero chart of accounts.</div>
          </div>
          <div className="form-group" style={{ marginBottom: 0 }}>
            <label>Xero tax rate</label><input value={taxType} disabled={busy} onChange={e => setTaxType(e.target.value)} placeholder="No Tax (0%)" />
            <div style={{ fontSize: 11, color: 'var(--text-muted)', marginTop: 3 }}>Use your Xero zero-tax rate name or <code>NONE</code>.</div>
          </div>
        </div>
        <div style={{ fontSize: 11.5, color: 'var(--text-muted)' }}>
          The CSV has one draft document per payment or refund, with the original invoice reference.
          Negative amounts import as credit notes. These rows match the Sales report; product item codes are omitted.
          Historical receipts without a confirmed invoice date remain pending review.
        </div>
      </div>
    </Modal>}
  </>;
};
