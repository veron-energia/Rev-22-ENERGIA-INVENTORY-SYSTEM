import React, { useCallback, useEffect, useId, useRef, useState } from 'react';
import { AlertTriangle, FileSpreadsheet } from 'lucide-react';
import { supabase } from '../../lib/supabase';
import { toXeroCsv } from '../../lib/xero/salesInvoiceTemplate.mjs';
import {
  type TikTokPayoutMonth, type TikTokPayoutPlan, type TikTokXeroCodes,
  buildTikTokPayoutRows, dayLabel, neededCodes, planTikTokPayouts, sgd, tiktokXeroFilename, weekLabel,
} from '../../lib/xero/tiktokPayouts.mjs';
import { Modal } from '../ui';

/**
 * TikTok's Wednesday payouts of a reporting month as a Xero Sales Invoice CSV
 * (the owner's rules, 1 Oct 2026). Owners and Managers; the page decides who
 * sees the button, and tiktok_xero_payouts (374) refuses anyone else.
 *
 * Every store together: TikTok pays the whole shop in one payout, whichever
 * store a file was imported into.
 */

const MONTHS = ['January','February','March','April','May','June','July','August','September','October','November','December'];
const NUM: React.CSSProperties = { textAlign: 'right', whiteSpace: 'nowrap' };

// The account codes are remembered on this computer, so they are typed once.
const CODES_KEY = 'energia.tiktokXeroCodes';
const DEFAULT_CODES: TikTokXeroCodes = { salesCode: '1011', feesCode: '', adsCode: '', taxType: 'No Tax (0%)' };
function loadCodes(): TikTokXeroCodes {
  try {
    const saved = JSON.parse(localStorage.getItem(CODES_KEY) || 'null');
    if (saved && typeof saved === 'object') {
      const pick = (k: keyof TikTokXeroCodes) => (typeof saved[k] === 'string' ? saved[k] : DEFAULT_CODES[k]);
      return { salesCode: pick('salesCode'), feesCode: pick('feesCode'), adsCode: pick('adsCode'), taxType: pick('taxType') };
    }
  } catch { /* no saved codes */ }
  return { ...DEFAULT_CODES };
}
function saveCodes(codes: TikTokXeroCodes) {
  try { localStorage.setItem(CODES_KEY, JSON.stringify(codes)); } catch { /* not remembered; still exported */ }
}

const STATUS_TEXT: Record<string, string> = {
  export: 'Export', not_finished: 'Not over yet', nothing: 'Nothing to pay',
};

const CodeField: React.FC<{
  label: string; hint: string; value: string; placeholder?: string; required: boolean;
  onChange: (value: string) => void;
}> = ({ label, hint, value, placeholder, required, onChange }) => {
  const id = useId();
  return (
    <div className="form-group" style={{ marginBottom: 0 }}>
      <label htmlFor={id}>{label}{required ? ' *' : ''}</label>
      <input id={id} value={value} placeholder={placeholder}
        aria-required={required} aria-describedby={`${id}-hint`} onChange={e => onChange(e.target.value)} />
      <div id={`${id}-hint`} style={{ fontSize: 11, color: 'var(--text-muted)', marginTop: 3 }}>{hint}</div>
    </div>
  );
};

export const TikTokXeroExportButton: React.FC<{ year: number; month: number }> = ({ year, month }) => {
  const [open, setOpen] = useState(false);
  const [loading, setLoading] = useState(false);
  const [plan, setPlan] = useState<TikTokPayoutPlan | null>(null);
  const [picked, setPicked] = useState<Record<string, boolean>>({});
  const [codes, setCodes] = useState<TikTokXeroCodes>(DEFAULT_CODES);
  const [err, setErr] = useState<string | null>(null);
  const [note, setNote] = useState<string | null>(null);
  // What was last downloaded: Export stays off until the ticks or codes change,
  // so one click cannot turn into two copies of the same invoices.
  const [exported, setExported] = useState<string | null>(null);
  // Only the latest request may set the payouts: an answer for a month no
  // longer asked about, or one that comes back after the dialog closed, is
  // dropped.
  const request = useRef(0);
  // One export at a time, and the same one only once: a click that lands
  // before the page has redrawn (a double click) sees these at once.
  const running = useRef(false);
  const lastExport = useRef<string | null>(null);

  const load = useCallback(async (y: number, m: number) => {
    const ticket = ++request.current;
    setPlan(null); setPicked({}); setErr(null); setNote(null); setExported(null); lastExport.current = null; setLoading(true);
    const { data, error } = await supabase.rpc('tiktok_xero_payouts', { p_year: y, p_month: m });
    if (ticket !== request.current) return;
    setLoading(false);
    if (error) { setErr(error.message); return; }
    try {
      const next = planTikTokPayouts(data as TikTokPayoutMonth);
      if (next.year !== y || next.month !== m) throw new Error('The payouts came back for another month. Close and open the export again.');
      setPlan(next);
      setPicked(Object.fromEntries(next.exportable.map(w => [w.payout_date, true])));
    } catch (e: any) { setErr(e.message || 'The payouts could not be read.'); }
  }, []);

  // Opened, or the month on the page changed while open: read that month.
  useEffect(() => { if (open) void load(year, month); }, [open, year, month, load]);

  const close = () => { request.current++; setLoading(false); setOpen(false); };
  const openDialog = () => { setCodes(loadCodes()); setOpen(true); };

  const chosen = plan ? plan.exportable.filter(w => picked[w.payout_date]).map(w => w.payout_date) : [];
  const exportKey = JSON.stringify([plan?.year, plan?.month, chosen, codes]);
  const run = () => {
    if (!plan || running.current || lastExport.current === exportKey) return;
    if (plan.year !== year || plan.month !== month) { setErr('The month changed. Wait for its payouts to load.'); return; }
    running.current = true;
    setErr(null); setNote(null);
    try {
      if (!chosen.length) throw new Error('Tick at least one Wednesday to export.');
      const { rows, headers, weeks, creditNotes, total } = buildTikTokPayoutRows(plan, codes, chosen);
      saveCodes(codes);
      const blob = new Blob([toXeroCsv(rows, headers)], { type: 'text/csv;charset=utf-8' });
      const url = URL.createObjectURL(blob);
      const link = document.createElement('a');
      link.href = url; link.download = tiktokXeroFilename(plan.year, plan.month);
      document.body.appendChild(link); link.click(); link.remove(); URL.revokeObjectURL(url);
      lastExport.current = exportKey; setExported(exportKey);
      const totalText = total.startsWith('-') ? `-S$${total.slice(1)}` : `S$${total}`;
      setNote(`Downloaded ${weeks} Wednesday payout${weeks === 1 ? '' : 's'}`
        + (creditNotes ? `, ${creditNotes} of them with a credit note` : '')
        + `, totalling ${totalText}. Review the drafts in Xero before approving them.`);
    } catch (e: any) { setErr(e.message || 'The export could not be prepared.'); }
    finally { running.current = false; }
  };

  const need = plan ? neededCodes(plan, chosen) : [];
  const chosenCents = plan ? plan.exportable.filter(w => picked[w.payout_date]).reduce((s, w) => s + w.cents.payout, 0) : 0;
  const allOver = !!plan && plan.weeks.every(w => w.status !== 'not_finished');
  const setCode = (k: keyof TikTokXeroCodes) => (value: string) => setCodes(c => ({ ...c, [k]: value }));
  const shownMonth = plan ? `${MONTHS[plan.month - 1]} ${plan.year}` : `${MONTHS[month - 1]} ${year}`;

  return <>
    <button className="btn btn-secondary btn-sm" onClick={openDialog}>
      <FileSpreadsheet size={14} /> Xero Export
    </button>
    {open && (
      <Modal title={`Export TikTok payouts for Xero — ${shownMonth}`} maxWidth={780} onClose={close}
        footer={<>
          <button className="btn btn-secondary" onClick={close}>Close</button>
          <button className="btn btn-primary" disabled={loading || !plan || chosen.length === 0 || exported === exportKey} onClick={run}>
            {exported === exportKey ? 'Downloaded' : 'Export CSV'}
          </button>
        </>}>
        <div className="form-grid" data-testid="tiktok-xero">
          <div style={{ fontSize: 12.5, color: 'var(--text-secondary)', lineHeight: 1.5 }}>
            TikTok pays the shop into the bank every Wednesday: everything settled from the Thursday before
            through that Wednesday, less the ads it took that week. Each Wednesday becomes one draft invoice to
            “TikTok Shop” whose total is that payout; a negative week gets a credit note.
            All stores together. A week can be exported once its Wednesday is over.
          </div>
          {loading && <div style={{ fontSize: 12.5, color: 'var(--text-muted)' }}>Working out the payouts…</div>}

          {plan && <>
            <div style={{ overflowX: 'auto' }}>
              <table data-testid="tiktok-xero-weeks">
                <thead><tr>
                  <th>Payout</th><th>Covers</th><th style={NUM}>Sales</th><th style={NUM}>Fees</th>
                  <th style={NUM}>Ads</th><th style={NUM}>Payout</th><th>Status</th>
                </tr></thead>
                <tbody>
                  {plan.weeks.map(w => (
                    <tr key={w.payout_date} data-week={w.payout_date}>
                      <td style={{ whiteSpace: 'nowrap' }}>{dayLabel(w.payout_date)}</td>
                      <td style={{ fontSize: 12 }}>{weekLabel(w)}</td>
                      <td style={NUM}>{sgd(w.cents.sales)}</td>
                      <td style={NUM}>{sgd(w.cents.fees)}</td>
                      <td style={NUM}>{sgd(w.cents.ads)}</td>
                      <td style={NUM}><strong>{sgd(w.cents.payout)}</strong></td>
                      <td style={{ whiteSpace: 'nowrap' }}>
                        {w.status === 'export' ? (
                          <label style={{ display: 'inline-flex', alignItems: 'center', gap: 6, margin: 0, fontWeight: 400 }}>
                            <input type="checkbox" style={{ width: 'auto' }} checked={!!picked[w.payout_date]}
                              aria-label={`Export the payout of ${dayLabel(w.payout_date)}`}
                              onChange={e => setPicked(p => ({ ...p, [w.payout_date]: e.target.checked }))} />
                            {STATUS_TEXT[w.status]}
                          </label>
                        ) : STATUS_TEXT[w.status]}
                        {w.warnings.length ? ' ⚠' : ''}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
            <div style={{ fontSize: 12.5 }} data-testid="tiktok-xero-total">
              Ticked: <strong>{sgd(chosenCents)}</strong> in {chosen.length} payout{chosen.length === 1 ? '' : 's'}.
              {' '}The month’s Total Income for every store is {sgd(plan.monthIncomeCents)}
              {!allOver ? ' (some Wednesdays are not over yet).'
                : plan.exportCents === plan.monthIncomeCents ? '; the Wednesdays add up to it.'
                : `; the Wednesdays add up to ${sgd(plan.exportCents)}. Check before exporting.`}
            </div>

            {(plan.monthWarnings.length > 0 || plan.weeks.some(w => w.warnings.length)) && (
              <div className="alert alert-warning" data-testid="tiktok-xero-warnings" style={{ marginBottom: 0 }}>
                <AlertTriangle size={15} />
                <div>
                  <div style={{ fontWeight: 600, marginBottom: 4 }}>Read before exporting</div>
                  <ul style={{ margin: 0, paddingLeft: 18 }}>
                    {plan.monthWarnings.map(t => <li key={t}>{t}</li>)}
                    {plan.weeks.flatMap(w => w.warnings.map(t => (
                      <li key={`${w.payout_date}:${t}`}><strong>{dayLabel(w.payout_date)}:</strong> {t}</li>
                    )))}
                  </ul>
                </div>
              </div>
            )}

            <div className="form-grid-2">
              <CodeField label="Account for TikTok sales" hint="Sales account in your Xero chart of accounts." placeholder="1011"
                value={codes.salesCode} required={need.includes('salesCode')} onChange={setCode('salesCode')} />
              <CodeField label="Account for TikTok fees" hint="For TikTok's Total Fees: commissions, affiliate commission, shipping and service fees."
                value={codes.feesCode} required={need.includes('feesCode')} onChange={setCode('feesCode')} />
              <CodeField label="Account for TikTok ads" hint="For the ads (GMV Pay) and subscriptions TikTok takes from the balance."
                value={codes.adsCode} required={need.includes('adsCode')} onChange={setCode('adsCode')} />
              <CodeField label="Xero tax rate" hint="Your Xero zero-tax rate name, or NONE." placeholder="No Tax (0%)"
                value={codes.taxType} required onChange={setCode('taxType')} />
            </div>
            <div style={{ fontSize: 11.5, color: 'var(--text-muted)' }}>
              Account codes are remembered on this computer. Invoice numbers are TT-PAYOUT-&lt;Wednesday&gt;, so untick
              the Wednesdays already in Xero before exporting again.
            </div>
          </>}

          {/* Next to the Export button, where they are seen. */}
          {err && <div className="alert alert-danger" role="alert" style={{ marginBottom: 0 }}><span>⚠</span><div>{err}</div></div>}
          {note && <div className="alert alert-info" role="status" style={{ marginBottom: 0 }}><div>{note}</div></div>}
        </div>
      </Modal>
    )}
  </>;
};
