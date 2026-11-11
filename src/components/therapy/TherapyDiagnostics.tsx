import React, { useCallback, useEffect, useState } from 'react';
import { RefreshCw } from 'lucide-react';
import { supabase } from '../../lib/supabase';
import { lengtheningCount } from '../../lib/catalogue/pageRules.mjs';
import './therapy.css';

/**
 * The "look before you touch anything" screen for therapy end dates
 * (Therapy → Holidays).
 *
 * It is a preview computed by the database and rendered here. Nothing is
 * written until somebody presses the button, and the destructive direction —
 * shortening an expiry — always needs a reason that is stored with the change;
 * this screen never asks for it, so it never shortens one.
 */

const fmt = (d: string | null) =>
  !d ? '—' : new Date(`${d}T12:00:00Z`).toLocaleDateString('en-GB',
    { day: '2-digit', month: 'short', year: 'numeric', timeZone: 'UTC' });

export const RecalculationPreview: React.FC<{ canManage: boolean }> = ({ canManage }) => {
  const [rows, setRows] = useState<any[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [result, setResult] = useState<any | null>(null);
  const [busy, setBusy] = useState(false);

  const load = useCallback(async () => {
    setBusy(true);
    const { data, error: e } = await supabase.rpc('therapy_recalculation_preview',
      { p_kind: null, p_customer_id: null });
    setBusy(false);
    if (e) { setError(e.message); setRows([]); return; }
    setError(null); setRows((data as any[]) ?? []);
  }, []);
  useEffect(() => { void load(); }, [load]);

  const changing = rows.filter(r => r.change_days !== null && r.change_days !== 0);
  const needCountry = rows.filter(r => r.needs_country);
  const shortening = rows.filter(r => r.shortens);
  const unverified = rows.filter(r => r.coverage && r.coverage.verified === false);
  const lengthening = lengtheningCount(rows);
  const lengtheningUnverified = lengtheningCount(rows.filter(r => r.coverage && r.coverage.verified === false));

  // Applying writes new expiry dates, so it asks first and says how many. The
  // server leaves out a period with no holiday country first, so one that
  // would also be shortened is counted once, under "no holiday country".
  const apply = async () => {
    const shortenSkipped = shortening.filter(r => !r.needs_country).length;
    const skipped = [
      shortenSkipped > 0 ? `${shortenSkipped} that would be shortened` : '',
      needCountry.length > 0 ? `${needCountry.length} with no holiday country` : '',
    ].filter(Boolean).join(' and ');
    const ok = window.confirm(
      `Lengthen ${lengthening} therapy period${lengthening === 1 ? '' : 's'}?\n\n` +
      'Each new expiry is the one shown under "Would become". No expiry is shortened.' +
      (skipped ? `\nLeft as they are: ${skipped}.` : '') +
      (lengtheningUnverified > 0
        ? `\n${lengtheningUnverified} of them run through a holiday calendar that has not been checked.` : ''));
    if (!ok) return;
    setBusy(true);
    const { data, error: e } = await supabase.rpc('therapy_apply_recalculation',
      { p_kind: null, p_customer_id: null, p_allow_shortening: false, p_reason: null });
    setBusy(false);
    if (e) { setError(e.message); return; }
    setResult(data); void load();
  };

  return (
    <div className="therapy-scope">
      <p className="therapy-remaining-hint">
        Every active and scheduled period of unlimited therapy, and what the current calendar
        would make its expiry. Nothing is written until you apply it, and applying it
        never shortens an expiry that has already been granted.
      </p>

      {error && <div className="alert alert-danger" role="alert">{error}</div>}

      <div className="therapy-card-stats" style={{ margin: '8px 0' }}>
        <span className="therapy-chip">{rows.length} active or scheduled</span>
        <span className="therapy-chip">{changing.length} would change</span>
        {needCountry.length > 0 && <span className="therapy-chip therapy-chip-warn">
          {needCountry.length} need a holiday country</span>}
        {shortening.length > 0 && <span className="therapy-chip therapy-chip-warn">
          {shortening.length} would be shortened — skipped</span>}
        {unverified.length > 0 && <span className="therapy-chip therapy-chip-warn">
          {unverified.length} span an unverified calendar</span>}
      </div>

      {result && (
        <div className="alert alert-success" role="status">
          Updated {result.updated}. Unchanged {result.unchanged}.
          Skipped: {result.skipped_needs_country} without a country,
          {' '}{result.skipped_would_shorten} that would have been shortened.
        </div>
      )}

      <div className="table-wrap therapy-desktop-only">
        <table>
          <thead>
            <tr>
              <th scope="col">Customer</th><th scope="col">No.</th><th scope="col">Source</th>
              <th scope="col">Country</th><th scope="col">Now</th><th scope="col">Would become</th>
              <th scope="col" className="therapy-num">Change</th><th scope="col">Notes</th>
            </tr>
          </thead>
          <tbody>
            {rows.length === 0 && !busy && (
              <tr><td colSpan={8} style={{ textAlign: 'center', color: 'var(--text-muted)', padding: 22 }}>
                No active or scheduled unlimited therapy.
              </td></tr>
            )}
            {rows.map(r => (
              <tr key={`${r.entitlement_kind}-${r.entitlement_id}`}>
                <td>{r.customer_name ?? '—'}</td>
                <td style={{ fontSize: 12 }}>{r.entitlement_no}</td>
                {/* The server names the source 'purchased' or 'legacy' (a period kept in
                    therapy_entitlements); staff read Purchased or Reward. */}
                <td><span className="therapy-chip">{r.entitlement_kind === 'purchased' ? 'Purchased' : 'Reward'}</span></td>
                <td>{r.holiday_country ?? <span className="therapy-chip therapy-chip-warn">none</span>}</td>
                <td style={{ fontSize: 12 }}>{fmt(r.current_expiry)}</td>
                <td style={{ fontSize: 12 }}>{fmt(r.proposed_expiry)}</td>
                <td className="therapy-num">
                  {r.change_days === null ? '—' : r.change_days > 0 ? `+${r.change_days}` : r.change_days}
                </td>
                <td style={{ fontSize: 11.5, color: 'var(--text-muted)' }}>
                  {r.shortens && <span className="therapy-chip therapy-chip-warn">would shorten — skipped</span>}
                  {r.coverage && !r.coverage.verified && <> calendar not verified</>}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      {canManage && (
        <button className="btn btn-primary btn-sm" style={{ marginTop: 10 }}
                onClick={() => void apply()} disabled={busy || lengthening === 0}>
          {busy ? 'Working…' : `Apply ${lengthening} lengthening change(s)`}
        </button>
      )}
      <button className="btn btn-secondary btn-sm" style={{ marginTop: 10, marginLeft: 8 }}
              onClick={() => void load()} disabled={busy}>
        <RefreshCw size={13} aria-hidden="true" /> Refresh
      </button>
    </div>
  );
};
