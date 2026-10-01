import React, { useRef, useState } from 'react';
import { AlertTriangle, FileSpreadsheet } from 'lucide-react';
import { supabase } from '../../lib/supabase';
import { singaporeToday } from '../../lib/invoices/business';
import { toXeroCsv } from '../../lib/xero/salesInvoiceTemplate.mjs';
import {
  type TikTokBankPayouts, buildBankPayoutRows, planBankPayouts, sgd, tiktokXeroFilename,
} from '../../lib/xero/tiktokPayouts.mjs';
import { Modal } from '../ui';

/**
 * TikTok's bank payouts between two dates as a Xero Sales Invoice CSV (the
 * owner's rules, 1 Oct 2026): one draft invoice per payout, one line for what
 * TikTok paid, on one account code. The payouts are TikTok's own Withdrawal
 * records, imported with the settlement files (375). Every store together:
 * TikTok pays the whole shop in one payout. Owners and Managers; the page
 * decides who sees the button, and tiktok_bank_payouts refuses anyone else.
 */
export const TikTokXeroExportButton: React.FC = () => {
  const [open, setOpen] = useState(false);
  const [from, setFrom] = useState('');
  const [to, setTo] = useState('');
  const [accountCode, setAccountCode] = useState('1011');
  const [taxType, setTaxType] = useState('No Tax (0%)');
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [note, setNote] = useState<string | null>(null);
  const [warnings, setWarnings] = useState<string[]>([]);
  // One export at a time: a second click while the first is building is ignored.
  const running = useRef(false);

  const run = async () => {
    if (running.current) return;
    if (!from || !to) { setErr('Choose both a start and an end date.'); return; }
    if (to < from) { setErr('The end date cannot be before the start date.'); return; }
    if (!accountCode.trim() || !taxType.trim()) { setErr('Enter the Xero account code and tax rate.'); return; }
    running.current = true;
    setBusy(true); setErr(null); setNote(null); setWarnings([]);
    try {
      const { data, error } = await supabase.rpc('tiktok_bank_payouts', { p_from: from, p_to: to });
      if (error) throw new Error(error.message);
      const plan = planBankPayouts(data as TikTokBankPayouts);
      setWarnings(plan.warnings);
      if (!plan.exportable.length) {
        setErr(plan.payoutCount
          ? 'None of the TikTok payouts between those dates can be exported: see the notes above.'
          : 'No TikTok payouts have been imported for those dates. They come from the Withdrawal records of TikTok\'s income files'
            + ' under Staged Imports; a file confirmed before its records were saved can be uploaded again and confirmed for its Withdrawal records.');
        return;
      }
      const { rows, headers, payouts, totalCents } = buildBankPayoutRows(plan, accountCode, taxType);
      const blob = new Blob([toXeroCsv(rows, headers)], { type: 'text/csv;charset=utf-8' });
      const url = URL.createObjectURL(blob);
      const link = document.createElement('a');
      link.href = url; link.download = tiktokXeroFilename(from, to);
      document.body.appendChild(link); link.click(); link.remove(); URL.revokeObjectURL(url);
      setNote(`Downloaded ${payouts} TikTok payout${payouts === 1 ? '' : 's'} totalling ${sgd(totalCents)}. Review the drafts in Xero before approving them.`);
    } catch (e: any) { setErr(e.message || 'Unable to prepare the TikTok export.'); }
    finally { setBusy(false); running.current = false; }
  };

  const openDialog = () => {
    const today = singaporeToday();
    setFrom(`${today.slice(0, 7)}-01`); setTo(today);
    setErr(null); setNote(null); setWarnings([]); setOpen(true);
  };

  return <>
    <button className="btn btn-secondary btn-sm" onClick={openDialog}><FileSpreadsheet size={14} /> Xero Export</button>
    {open && <Modal title="Export TikTok payouts for Xero" maxWidth={560} onClose={() => { if (!busy) setOpen(false); }}
      footer={<>
        <button className="btn btn-secondary" disabled={busy} onClick={() => setOpen(false)}>Close</button>
        <button className="btn btn-primary" onClick={() => void run()} disabled={busy}>{busy ? 'Building…' : 'Export CSV'}</button>
      </>}>
      <div className="form-grid" data-testid="tiktok-xero">
        <div style={{ fontSize: 12.5, color: 'var(--text-secondary)' }}>
          One draft invoice to “TikTok Shop” for each payout TikTok paid into the bank between the dates (every
          Wednesday), for exactly what TikTok paid. All stores together.
        </div>
        <div className="form-grid-2">
          <div className="form-group" style={{ marginBottom: 0 }}>
            <label htmlFor="tiktok-xero-from">From *</label>
            <input id="tiktok-xero-from" type="date" value={from} disabled={busy} onChange={e => setFrom(e.target.value)} />
          </div>
          <div className="form-group" style={{ marginBottom: 0 }}>
            <label htmlFor="tiktok-xero-to">To *</label>
            <input id="tiktok-xero-to" type="date" value={to} min={from} disabled={busy} onChange={e => setTo(e.target.value)} />
          </div>
        </div>
        <div className="form-grid-2">
          <div className="form-group" style={{ marginBottom: 0 }}>
            <label htmlFor="tiktok-xero-code">Xero account code</label>
            <input id="tiktok-xero-code" value={accountCode} disabled={busy} onChange={e => setAccountCode(e.target.value)} placeholder="1011" />
            <div style={{ fontSize: 11, color: 'var(--text-muted)', marginTop: 3 }}>Sales account in your Xero chart of accounts.</div>
          </div>
          <div className="form-group" style={{ marginBottom: 0 }}>
            <label htmlFor="tiktok-xero-tax">Xero tax rate</label>
            <input id="tiktok-xero-tax" value={taxType} disabled={busy} onChange={e => setTaxType(e.target.value)} placeholder="No Tax (0%)" />
            <div style={{ fontSize: 11, color: 'var(--text-muted)', marginTop: 3 }}>Use your Xero zero-tax rate name or <code>NONE</code>.</div>
          </div>
        </div>
        {warnings.length > 0 && (
          <div className="alert alert-warning" data-testid="tiktok-xero-warnings" style={{ marginBottom: 0 }}>
            <AlertTriangle size={15} />
            <div>
              <div style={{ fontWeight: 600, marginBottom: 4 }}>Check these</div>
              <ul style={{ margin: 0, paddingLeft: 18 }}>{warnings.map(t => <li key={t}>{t}</li>)}</ul>
            </div>
          </div>
        )}
        {err && <div className="alert alert-danger" role="alert" style={{ marginBottom: 0 }}><span>⚠</span><div>{err}</div></div>}
        {note && <div className="alert alert-info" role="status" style={{ marginBottom: 0 }}><div>{note}</div></div>}
      </div>
    </Modal>}
  </>;
};
