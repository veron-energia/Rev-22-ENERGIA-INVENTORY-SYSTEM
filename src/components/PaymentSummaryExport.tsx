import React, { useState } from 'react';
import * as XLSX from 'xlsx';
import { CalendarRange } from 'lucide-react';
import { supabase } from '../lib/supabase';
import { Modal } from './ui';

/**
 * Daily takings by payment method, as a cross-tab: one row per day, one column
 * per method, with a total column down the right and a total row along the
 * bottom.
 *
 * The figures come from a single database aggregate rather than from whatever
 * the page happens to have loaded, so the sheet covers every payment in the
 * range instead of only the current page of invoices.
 */
export const PaymentSummaryExport: React.FC<{
  stores: { id: string; name: string }[];
  defaultStoreId?: string;
}> = ({ stores, defaultStoreId = '' }) => {
  const [open, setOpen] = useState(false);
  const [from, setFrom] = useState('');
  const [to, setTo] = useState('');
  const [storeId, setStoreId] = useState(defaultStoreId);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);

  const money = (n: number) => Math.round((n + Number.EPSILON) * 100) / 100;

  const run = async () => {
    if (!from || !to) { setErr('Choose both a start and an end date.'); return; }
    if (to < from) { setErr('The end date cannot be before the start date.'); return; }
    setBusy(true); setErr(null);

    // PostgREST caps a response at 1000 rows, and this cross-tab returns one row
    // per day PER METHOD: a year across three methods is 1095. Unpaginated, the
    // later days would simply be absent from the sheet with no error. Paged.
    const fetchAllRpc = async (fn: string, args: Record<string, any>) => {
      const PAGE = 1000;
      const out: any[] = [];
      for (let offset = 0; ; offset += PAGE) {
        const { data, error } = await supabase.rpc(fn, args).range(offset, offset + PAGE - 1);
        if (error) throw new Error(error.message);
        const batch = (data as any[]) ?? [];
        out.push(...batch);
        if (batch.length < PAGE) break;
      }
      return out;
    };

    let methods: any[] = [], rows: any[] = [];
    try {
      const args = { p_from: from, p_to: to, p_store_id: storeId || null };
      [methods, rows] = await Promise.all([
        fetchAllRpc('payment_methods_in_range', args),
        fetchAllRpc('daily_payments_by_method', args),
      ]);
    } catch (e: any) { setBusy(false); setErr(e.message); return; }
    setBusy(false);
    if (methods.length === 0) {
      setErr('No payments were taken in that range.');
      return;
    }

    // Pivot: date -> method -> amount.
    const byDate = new Map<string, Record<string, number>>();
    for (const r of rows) {
      const d = String(r.pay_date);
      if (!byDate.has(d)) byDate.set(d, {});
      byDate.get(d)![r.method_name] = Number(r.amount) || 0;
    }

    const dates = [...byDate.keys()].sort();
    const headers = ['Date', ...methods.map((m: any) => m.method_name), 'Total'];
    const columnTotals: Record<string, number> = {};
    let grand = 0;

    const body = dates.map(d => {
      const cells = byDate.get(d) ?? {};
      const o: Record<string, any> = {
        // Written as text in the local format so a spreadsheet does not
        // reinterpret it as an American date.
        Date: new Date(`${d}T00:00:00`).toLocaleDateString('en-GB'),
      };
      let rowTotal = 0;
      for (const m of methods) {
        const v = money(cells[m.method_name] ?? 0);
        o[m.method_name] = v;
        rowTotal += v;
        columnTotals[m.method_name] = money((columnTotals[m.method_name] ?? 0) + v);
      }
      o.Total = money(rowTotal);
      grand = money(grand + rowTotal);
      return o;
    });

    // The total row along the bottom.
    const totalRow: Record<string, any> = { Date: 'TOTAL' };
    for (const m of methods) totalRow[m.method_name] = money(columnTotals[m.method_name] ?? 0);
    totalRow.Total = grand;
    body.push(totalRow);

    const ws = XLSX.utils.json_to_sheet(body, { header: headers });
    ws['!cols'] = headers.map(h => ({ wch: h === 'Date' ? 14 : Math.max(12, h.length + 2) }));

    const wb = XLSX.utils.book_new();
    XLSX.utils.book_append_sheet(wb, ws, 'Daily Payments');
    const storeName = storeId ? (stores.find(s => s.id === storeId)?.name ?? 'store') : 'all-stores';
    XLSX.writeFile(wb, `daily-payments-${storeName}-${from}-to-${to}.xlsx`.replace(/\s+/g, '-'));
    setOpen(false);
  };

  const openDialog = () => {
    // Default to the month so far, which is what this is usually wanted for.
    const now = new Date();
    const first = new Date(now.getFullYear(), now.getMonth(), 1);
    setFrom(first.toISOString().slice(0, 10));
    setTo(now.toISOString().slice(0, 10));
    setStoreId(defaultStoreId);
    setErr(null);
    setOpen(true);
  };

  return (
    <>
      <button className="btn btn-secondary" onClick={openDialog}>
        <CalendarRange size={15} /> Payment Summary
      </button>

      {open && (
        <Modal title="Daily takings by payment method" maxWidth={520} onClose={() => setOpen(false)}
          footer={<>
            <button className="btn btn-secondary" onClick={() => setOpen(false)}>Cancel</button>
            <button className="btn btn-primary" onClick={run} disabled={busy}>
              {busy ? 'Building…' : 'Export Excel'}
            </button>
          </>}>
          <div className="form-grid">
            <div style={{ fontSize: 12.5, color: 'var(--text-secondary)' }}>
              One row per day, one column per payment method, with totals down the right and
              along the bottom. Dated by <strong>when the payment was taken</strong>, so a
              settled balance counts on the day the money arrived.
            </div>

            {err && <div className="alert alert-danger" style={{ marginBottom: 0 }}>
              <span>⚠</span><div>{err}</div></div>}

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

            <div className="form-group" style={{ marginBottom: 0 }}>
              <label>Store</label>
              <select value={storeId} onChange={e => setStoreId(e.target.value)}>
                <option value="">All stores</option>
                {stores.map(s => <option key={s.id} value={s.id}>{s.name}</option>)}
              </select>
            </div>

            <div style={{ fontSize: 11.5, color: 'var(--text-muted)' }}>
              Days with no takings are included as zeroes, so a gap is visible rather than
              missing. Refunds are not deducted — this reports what was collected.
            </div>
          </div>
        </Modal>
      )}
    </>
  );
};
