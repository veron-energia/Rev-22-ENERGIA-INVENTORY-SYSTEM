import React, { useState } from 'react';
import * as XLSX from 'xlsx';
import { FileSpreadsheet } from 'lucide-react';
import { supabase } from '../lib/supabase';
import { Modal } from './ui';

/**
 * Xero sales-invoice export.
 *
 * Produces the column set Xero expects for its Sales Invoice import, with ONE
 * ROW PER INVOICE LINE and the header fields (contact, invoice number, dates)
 * repeated on every line of the same invoice — which is how Xero groups lines
 * back into one invoice on import.
 *
 * TOTALS MUST RECONCILE. Two things are handled so the sum of the exported
 * lines equals the invoice total exactly:
 *
 *   * a line's own discount is netted off its unit amount;
 *   * an invoice-level discount (manual or voucher) belongs to no single line,
 *     so it is written as its own negative line. Spreading it across the lines
 *     would introduce rounding differences of a cent or two per invoice, which
 *     is exactly the kind of thing someone has to chase later.
 *
 * The invoice is exported at its FULL value even when part was settled with
 * wallet credit: credit is a payment method, and the invoice was still issued
 * for the whole amount. How it was paid is a separate matter in Xero.
 */
export const XeroExportButton: React.FC<{
  stores: { id: string; name: string }[];
  defaultStoreId?: string;
}> = ({ stores, defaultStoreId = '' }) => {
  const [open, setOpen] = useState(false);
  const [from, setFrom] = useState('');
  const [to, setTo] = useState('');
  const [storeId, setStoreId] = useState(defaultStoreId);
  const [accountCode, setAccountCode] = useState('200');
  // Xero REJECTS an invoice line whose InventoryItemCode is not already an item
  // in the Xero organisation. Energia's SKUs almost certainly are not, so the
  // column is left blank unless it is deliberately turned on — otherwise the
  // very first import fails on every line.
  const [sendSkus, setSendSkus] = useState(false);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [note, setNote] = useState<string | null>(null);

  // Xero reads dates in the organisation's locale; dd/mm/yyyy is what a
  // Singapore org expects, and writing it as text stops Excel reinterpreting it.
  const xeroDate = (d?: string | null) => {
    if (!d) return '';
    const dt = new Date(d);
    if (isNaN(dt.getTime())) return '';
    const p = (n: number) => String(n).padStart(2, '0');
    return `${p(dt.getDate())}/${p(dt.getMonth() + 1)}/${dt.getFullYear()}`;
  };
  const round2 = (n: number) => Math.round((n + Number.EPSILON) * 100) / 100;

  // PostgREST caps a request at 1000 rows. Every fetch below was written as a
  // single call, so anything larger was SILENTLY TRUNCATED:
  //
  //   * customers — Energia has far more than 1000, so an invoice whose customer
  //     sat beyond the first page fell back to "Walk-in customer";
  //   * invoice_items — worse: a month can easily exceed 1000 lines, and the
  //     missing ones would have imported invoices into Xero with lines absent
  //     and totals short;
  //   * invoices themselves, for a long enough range.
  //
  // Nothing errors when this happens, which is why it looked like a naming bug.
  const fetchAll = async <T,>(
    build: (offset: number, limit: number) => any
  ): Promise<T[]> => {
    const PAGE = 1000;
    const out: T[] = [];
    for (let offset = 0; ; offset += PAGE) {
      const { data, error } = await build(offset, PAGE);
      if (error) throw new Error(error.message);
      const batch = (data as T[]) ?? [];
      out.push(...batch);
      if (batch.length < PAGE) break;
    }
    return out;
  };

  // An "in" list is also limited by URL length, so ids are queried in chunks.
  const fetchByIds = async <T,>(
    table: string, columns: string, column: string, ids: string[]
  ): Promise<T[]> => {
    const CHUNK = 200;
    const out: T[] = [];
    for (let i = 0; i < ids.length; i += CHUNK) {
      const slice = ids.slice(i, i + CHUNK);
      const rows = await fetchAll<T>((offset, limit) =>
        supabase.from(table).select(columns).in(column, slice).range(offset, offset + limit - 1));
      out.push(...rows);
    }
    return out;
  };

  const run = async () => {
    if (!from || !to) { setErr('Choose both a start and an end date.'); return; }
    if (to < from) { setErr('The end date cannot be before the start date.'); return; }
    setBusy(true); setErr(null); setNote(null);

    // Settled invoices only: a draft or unpaid invoice should not be posted to
    // the accounts, and a cancelled or refunded one certainly should not.
    let invoices: any[] = [];
    try {
      invoices = await fetchAll<any>((offset, limit) => {
        let q = supabase.from('invoices')
          .select('*')
          .is('deleted_at', null)
          .in('status', ['paid', 'partially_paid', 'completed_foc'])
          .gte('created_at', `${from}T00:00:00`)
          .lte('created_at', `${to}T23:59:59`)
          .order('created_at')
          .range(offset, offset + limit - 1);
        if (storeId) q = q.eq('store_id', storeId);
        return q;
      });
    } catch (e: any) { setBusy(false); setErr(e.message); return; }
    if (invoices.length === 0) {
      setBusy(false);
      setErr('No settled invoices in that range.');
      return;
    }

    const ids = invoices.map(i => i.id);
    // Only the customers these invoices actually reference — far lighter than
    // reading the whole book, and immune to the row cap.
    const custIds = Array.from(new Set(
      invoices.map(i => i.customer_id).filter((x): x is string => !!x)));

    let itemRows: any[] = [], custRows: any[] = [];
    let prodRows: any[] = [], vouRows: any[] = [], promoRows: any[] = [];
    let therRows: any[] = [], specRows: any[] = [];
    try {
      [itemRows, custRows, prodRows, vouRows, promoRows, therRows, specRows] = await Promise.all([
        fetchByIds<any>('invoice_items', '*', 'invoice_id', ids),
        fetchByIds<any>('customers', 'id,full_name,email,phone,address', 'id', custIds),
        fetchAll<any>((o, l) => supabase.from('products').select('id,name,sku').range(o, o + l - 1)),
        fetchAll<any>((o, l) => supabase.from('vouchers').select('id,name').range(o, o + l - 1)),
        fetchAll<any>((o, l) => supabase.from('promotions').select('id,name').range(o, o + l - 1)),
        fetchAll<any>((o, l) => supabase.from('unlimited_therapy_packages').select('id,name').range(o, o + l - 1)),
        fetchAll<any>((o, l) => supabase.from('special_products').select('id,name,sku').range(o, o + l - 1)),
      ]);
    } catch (e: any) { setBusy(false); setErr(e.message); return; }


    const nameMap = (rows: any[]) => new Map((rows ?? []).map(r => [r.id, r.name]));
    const products = new Map((prodRows ?? []).map(r => [r.id, r]));
    const vouchers = nameMap(vouRows);
    const promotions = nameMap(promoRows);
    const therapies = nameMap(therRows);
    const specials = new Map((specRows ?? []).map(r => [r.id, r]));

    const describe = (it: any): string => {
      switch (it.line_kind) {
        case 'voucher':        return vouchers.get(it.voucher_id) ?? 'Voucher';
        case 'promotion':      return promotions.get(it.promotion_id) ?? 'Promotion';
        case 'premium_bundle': return promotions.get(it.promotion_id) ?? 'Bundle';
        case 'therapy':        return therapies.get(it.therapy_package_id) ?? 'Therapy package';
        case 'credit_package': return 'Credit package';
        case 'special_product':
        case 'rental':         return specials.get(it.special_product_id)?.name
                                      ?? (it.line_kind === 'rental' ? 'Rental' : 'Special product');
        default:               return products.get(it.product_id)?.name ?? 'Item';
      }
    };
    const itemCode = (it: any): string =>
      products.get(it.product_id)?.sku ?? specials.get(it.special_product_id)?.sku ?? '';

    const itemsByInvoice = new Map<string, any[]>();
    for (const it of (itemRows ?? [])) {
      const list = itemsByInvoice.get(it.invoice_id) ?? [];
      list.push(it);
      itemsByInvoice.set(it.invoice_id, list);
    }
    const customer = new Map((custRows ?? []).map(c => [c.id, c]));

    const HEADERS = [
      '*ContactName', 'EmailAddress', 'POAddressLine1', 'POCity', 'POPostalCode', 'POCountry',
      '*InvoiceNumber', 'Reference', '*InvoiceDate', '*DueDate',
      'InventoryItemCode', '*Description', '*Quantity', '*UnitAmount',
      '*AccountCode', '*TaxType', 'TaxAmount', 'Currency',
    ];

    const body: Record<string, any>[] = [];
    let mismatches = 0;

    let skippedUnpaid = 0;
    for (const inv of invoices) {
      // Nothing received yet, so on a cash basis there is nothing to post. It
      // would otherwise import as an invoice of zero, which is just noise in
      // the accounts. It will appear once the customer pays.
      if (round2(Number(inv.paid_amount ?? 0)) <= 0) { skippedUnpaid += 1; continue; }
      const c = customer.get(inv.customer_id);
      const lines = itemsByInvoice.get(inv.id) ?? [];
      const head = {
        '*ContactName': c?.full_name || 'Walk-in customer',
        EmailAddress: c?.email ?? '',
        POAddressLine1: c?.address ?? '',
        POCity: '', POPostalCode: '', POCountry: 'Singapore',
        '*InvoiceNumber': inv.invoice_no,
        Reference: inv.notes ?? '',
        '*InvoiceDate': xeroDate(inv.created_at),
        // No separate due date is held: these are settled at point of sale.
        '*DueDate': xeroDate(inv.paid_at ?? inv.created_at),
        '*AccountCode': accountCode,
        // Not GST-registered: NONE is Xero's no-tax type.
        '*TaxType': 'NONE',
        TaxAmount: 0,
        Currency: 'SGD',
      };

      // A partially paid invoice is exported at WHAT HAS BEEN PAID, not what was
      // billed. Every line is scaled by the same proportion, so the descriptions
      // and quantities still read correctly and the total ties to the money
      // received. A fully paid invoice has a ratio of 1 and is untouched.
      const billed = round2(Number(inv.total_amount ?? 0));
      const received = round2(Number(inv.paid_amount ?? 0));
      const paidRatio = billed > 0 ? Math.min(received / billed, 1) : 0;

      let lineSum = 0;
      for (const it of lines) {
        const qty = Number(it.quantity ?? 0) || 0;
        const gross = Number(it.line_total ?? 0);
        const lineDisc = Number(it.line_discount ?? 0);
        const net = round2((gross - lineDisc) * paidRatio);
        // Xero multiplies Quantity by UnitAmount, so the unit amount carries the
        // line's discount rather than the discount being lost.
        const unit = qty > 0 ? round2(net / qty) : net;
        lineSum = round2(lineSum + round2(unit * qty));

        body.push({
          ...head,
          InventoryItemCode: sendSkus ? itemCode(it) : '',
          '*Description': describe(it),
          '*Quantity': qty || 1,
          '*UnitAmount': unit,
        });
      }

      // Invoice-level discount as its own line, so the totals agree exactly.
      const invDisc = round2(Number(inv.discount_total ?? 0) * paidRatio);
      if (invDisc > 0) {
        body.push({
          ...head,
          InventoryItemCode: '',
          '*Description': 'Invoice discount',
          '*Quantity': 1,
          '*UnitAmount': -invDisc,
        });
        lineSum = round2(lineSum - invDisc);
      }

      // A row with no lines at all would import as an empty invoice.
      if (lines.length === 0 && invDisc === 0) {
        body.push({
          ...head,
          InventoryItemCode: '',
          '*Description': 'Invoice ' + inv.invoice_no,
          '*Quantity': 1,
          '*UnitAmount': received,
        });
        lineSum = received;
      }

      // Xero computes each line as Quantity x UnitAmount, so a line that does
      // not divide evenly leaves a cent behind: 100.00 over 3 units becomes
      // 33.33 x 3 = 99.99. Rather than let the invoice import a cent light, the
      // difference is written as its own rounding line. It is visible in the
      // accounts, which is the point — a silent penny is worse than a stated one.
      // Reconcile against what is actually being exported. Where an invoice has
      // been OVERPAID the ratio is clamped at 1, so the exported value is the
      // billed amount and the excess is not invented as revenue — an overpayment
      // is a credit owed to the customer, not a sale. Comparing against the
      // received figure there would flag a mismatch that is not one.
      const target = Math.min(received, billed > 0 ? billed : received);
      const drift = round2(target - lineSum);
      if (drift !== 0 && Math.abs(drift) <= 0.05) {
        body.push({
          ...head,
          InventoryItemCode: '',
          '*Description': 'Rounding',
          '*Quantity': 1,
          '*UnitAmount': drift,
        });
        lineSum = round2(lineSum + drift);
      }

      // Anything larger than a rounding cent is a real discrepancy and is
      // reported rather than papered over.
      if (Math.abs(lineSum - target) > 0.01) mismatches += 1;
    }

    const ws = XLSX.utils.json_to_sheet(body, { header: HEADERS });
    ws['!cols'] = HEADERS.map(h => ({ wch: Math.max(12, Math.min(h.length + 4, 28)) }));
    const wb = XLSX.utils.book_new();
    XLSX.utils.book_append_sheet(wb, ws, 'Xero Invoices');
    const scope = storeId ? (stores.find(s => s.id === storeId)?.name ?? 'store') : 'all-stores';
    XLSX.writeFile(wb, `xero-invoices-${scope}-${from}-to-${to}.xlsx`.replace(/\s+/g, '-'));

    setBusy(false);
    const notes: string[] = [];
    if (skippedUnpaid > 0) {
      notes.push(`${skippedUnpaid} invoice(s) with nothing paid yet were left out — they will appear once payment is taken.`);
    }
    if (mismatches > 0) {
      // Reported rather than hidden: a total that does not tie out is something
      // to look at before importing into the accounts.
      notes.push(`${mismatches} invoice(s) did not tie to the amount paid — check those before importing.`);
    }
    if (notes.length > 0) {
      setNote(notes.join(' '));
    } else {
      setOpen(false);
    }
  };

  const openDialog = () => {
    const now = new Date();
    const first = new Date(now.getFullYear(), now.getMonth(), 1);
    setFrom(first.toISOString().slice(0, 10));
    setTo(now.toISOString().slice(0, 10));
    setStoreId(defaultStoreId);
    setErr(null); setNote(null);
    setOpen(true);
  };

  return (
    <>
      <button className="btn btn-secondary" onClick={openDialog}>
        <FileSpreadsheet size={15} /> Xero Export
      </button>

      {open && (
        <Modal title="Export invoices for Xero" maxWidth={560} onClose={() => setOpen(false)}
          footer={<>
            <button className="btn btn-secondary" onClick={() => setOpen(false)}>Close</button>
            <button className="btn btn-primary" onClick={run} disabled={busy}>
              {busy ? 'Building…' : 'Export Excel'}
            </button>
          </>}>
          <div className="form-grid">
            <div style={{ fontSize: 12.5, color: 'var(--text-secondary)' }}>
              Xero's Sales Invoice import layout — one row per invoice line, with the contact
              and invoice details repeated on each line. Only <strong>settled</strong> invoices
              are included; drafts, unpaid, cancelled and refunded invoices are left out.
            </div>

            {err && <div className="alert alert-danger" style={{ marginBottom: 0 }}>
              <span>⚠</span><div>{err}</div></div>}
            {note && <div className="alert alert-warning" style={{ marginBottom: 0 }}>
              <span>⚠</span><div>{note}</div></div>}

            <div className="form-grid-2">
              <div className="form-group" style={{ marginBottom: 0 }}>
                <label>From *</label>
                <input type="date" value={from} onChange={e => setFrom(e.target.value)} />
              </div>
              <div className="form-group" style={{ marginBottom: 0 }}>
                <label>To *</label>
                <input type="date" value={to} min={from} onChange={e => setTo(e.target.value)} />
              </div>
            </div>

            <div className="form-grid-2">
              <div className="form-group" style={{ marginBottom: 0 }}>
                <label>Store</label>
                <select value={storeId} onChange={e => setStoreId(e.target.value)}>
                  <option value="">All stores</option>
                  {stores.map(s => <option key={s.id} value={s.id}>{s.name}</option>)}
                </select>
              </div>
              <div className="form-group" style={{ marginBottom: 0 }}>
                <label>Xero account code</label>
                <input value={accountCode} onChange={e => setAccountCode(e.target.value)}
                  placeholder="200" />
                <div style={{ fontSize: 11, color: 'var(--text-muted)', marginTop: 3 }}>
                  Sales account in your Xero chart of accounts.
                </div>
              </div>
            </div>

            <label style={{ display: 'flex', gap: 8, alignItems: 'flex-start', fontSize: 12.5 }}>
              <input type="checkbox" style={{ width: 'auto', marginTop: 2 }}
                checked={sendSkus} onChange={e => setSendSkus(e.target.checked)} />
              <span>
                Include product SKUs as Xero item codes
                <div style={{ fontSize: 11, color: 'var(--text-muted)' }}>
                  Leave this off unless the same codes already exist as items in Xero — Xero
                  rejects a line whose item code it does not recognise.
                </div>
              </span>
            </label>

            <div style={{ fontSize: 11.5, color: 'var(--text-muted)' }}>
              Tax type is set to <strong>NONE</strong> (not GST-registered). An invoice-level
              discount is written as its own negative line so the total ties out exactly.
              Invoices are exported at full value — wallet credit is a way of paying, so how it
              was settled is recorded separately in Xero.
            </div>
          </div>
        </Modal>
      )}
    </>
  );
};
