import React, { useCallback, useEffect, useState } from 'react';
import { AlertTriangle, RefreshCw } from 'lucide-react';
import { supabase } from '../../lib/supabase';
import './therapy.css';

/**
 * The two "look before you touch anything" screens.
 *
 * Both are previews computed by the database and rendered here. Neither writes
 * anything until somebody presses the button, and the destructive direction —
 * shortening an expiry, attaching a historical entitlement to a different
 * tier — always needs a reason that is stored with the change.
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

  const apply = async () => {
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
        Every active and scheduled unlimited entitlement, and what the current calendar
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
              <th scope="col">Customer</th><th scope="col">Entitlement</th><th scope="col">Source</th>
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
                <td><span className="therapy-chip">{r.entitlement_kind}</span></td>
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
                onClick={() => void apply()} disabled={busy || changing.length === 0}>
          {busy ? 'Working…' : `Apply ${changing.length - shortening.length} lengthening change(s)`}
        </button>
      )}
      <button className="btn btn-secondary btn-sm" style={{ marginTop: 10, marginLeft: 8 }}
              onClick={() => void load()} disabled={busy}>
        <RefreshCw size={13} aria-hidden="true" /> Refresh
      </button>
    </div>
  );
};

export const RewardMappingPreview: React.FC<{ canManage: boolean; onChanged?: () => void }> =
  ({ canManage, onChanged }) => {
  const [rows, setRows] = useState<any[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const load = useCallback(async () => {
    setBusy(true);
    const { data, error: e } = await supabase.rpc('therapy_reward_mapping_preview');
    setBusy(false);
    if (e) { setError(e.message); setRows([]); return; }
    setError(null); setRows((data as any[]) ?? []);
  }, []);
  useEffect(() => { void load(); }, [load]);

  const stranded = rows.filter(r => Number(r.option_count) === 0);

  const map = async (row: any, tierKey: string, thresholdDiffers: boolean) => {
    const reason = window.prompt(
      `Map ${row.entitlement_no} (earned at S$${row.qualifying_amount}) to this reward tier?\n\n` +
      (thresholdDiffers
        ? 'This tier has a DIFFERENT qualifying threshold. Only do this if you have\n' +
          'confirmed from records that it offered the same alternatives.\n\n'
        : '') +
      'Reason (stored with the change):');
    if (!reason || !reason.trim()) return;
    const { error: e } = await supabase.rpc('therapy_map_entitlement_tier',
      { p_entitlement_id: row.entitlement_id, p_tier_key: tierKey, p_reason: reason.trim() });
    if (e) { setError(e.message); return; }
    setNotice(`${row.entitlement_no} mapped. Its qualifying amount is unchanged.`);
    void load(); onChanged?.();
  };

  return (
    <div className="therapy-scope">
      <p className="therapy-remaining-hint">
        Unclaimed entitlements and the reward alternatives available to each. An entitlement
        earned under an older threshold matches no current rule, so it offers no choice at all
        until somebody confirms which tier it belongs to. Nothing is attached automatically:
        a rule at a different threshold is a different promise.
      </p>

      {error && <div className="alert alert-danger" role="alert">{error}</div>}
      {notice && <div className="alert alert-success" role="status">{notice}</div>}

      <div className="therapy-card-stats" style={{ margin: '8px 0' }}>
        <span className="therapy-chip">{rows.length} unclaimed</span>
        {stranded.length > 0 && (
          <span className="therapy-chip therapy-chip-warn">{stranded.length} with no reward options</span>
        )}
      </div>

      {rows.length === 0 && !busy && (
        <p className="therapy-remaining-hint">No unclaimed entitlements.</p>
      )}

      {rows.map(r => (
        <div className="therapy-card" key={r.entitlement_id}>
          <div className="therapy-card-head">
            <div>
              <div className="therapy-card-name">{r.customer_name ?? '—'}</div>
              <div className="therapy-remaining-hint">
                {r.entitlement_no} · {r.recipient} · earned at S${r.qualifying_amount} ·
                claim by {fmt(r.activation_deadline)}
              </div>
            </div>
            <span className={`therapy-chip${Number(r.option_count) === 0 ? ' therapy-chip-warn' : ''}`}>
              {r.option_count} option{Number(r.option_count) === 1 ? '' : 's'}
            </span>
          </div>

          {Number(r.option_count) === 0 && (
            <div className="alert alert-warning" role="status" style={{ marginTop: 8 }}>
              <AlertTriangle size={14} aria-hidden="true" />
              <div>
                This entitlement currently offers no choice. Its threshold no longer matches
                any active rule, so the claim dialog would have nothing to show.
              </div>
            </div>
          )}

          {canManage && (r.candidates ?? []).length > 0 && Number(r.option_count) === 0 && (
            <div style={{ marginTop: 8 }}>
              <div className="therapy-remaining-hint" style={{ marginBottom: 4 }}>Candidate tiers:</div>
              {(r.candidates ?? []).map((c: any) => (
                <div className="therapy-basket-row" key={c.tier_key}>
                  <span>
                    <strong>S${c.qualifying_amount}</strong> — {(c.names ?? []).join(' or ')}
                    {c.threshold_differs && (
                      <span className="therapy-chip therapy-chip-warn" style={{ marginLeft: 6 }}>
                        different threshold
                      </span>
                    )}
                  </span>
                  <button className="btn btn-secondary btn-sm"
                          onClick={() => void map(r, c.tier_key, c.threshold_differs)}>
                    Map to this tier
                  </button>
                  <span />
                </div>
              ))}
            </div>
          )}
        </div>
      ))}

      <button className="btn btn-secondary btn-sm" onClick={() => void load()} disabled={busy}>
        <RefreshCw size={13} aria-hidden="true" /> Refresh
      </button>
    </div>
  );
};
