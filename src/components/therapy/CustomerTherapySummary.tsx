import React, { useCallback, useEffect, useMemo, useState } from 'react';
import { ChevronDown, ChevronRight, RefreshCw, Search } from 'lucide-react';
import { supabase } from '../../lib/supabase';
import { ExpiryExplanation, CoverageNotice } from './ExpiryExplanation';
import './therapy.css';

/**
 * What each customer actually holds, from the authoritative issued records.
 *
 * Totals are computed in the database over the whole set and only then paged,
 * so the number beside a customer's name never depends on how many rows this
 * page happened to fetch. The row count is reported for the same reason: a list
 * that silently stops at 50 is worse than one that says it did.
 *
 * Therapy vouchers and money-off vouchers are shown in separate columns. They
 * are different units — a session and a dollar — and adding them would produce
 * a number that means nothing.
 */

interface SummaryRow {
  customer_id: string; customer_name: string; customer_phone: string;
  therapy_vouchers_issued: number; therapy_vouchers_redeemed: number;
  therapy_vouchers_remaining: number; money_vouchers_remaining: number;
  vouchers_revoked: number;
  unlimited_active: number; unlimited_scheduled: number;
  unlimited_pending: number; unlimited_finished: number;
  current_unlimited_expiry: string | null;
  current_unlimited_days_remaining: number | null;
  next_unlimited_start: string | null;
  needs_review: boolean; total_customers: number;
}

const PAGE = 50;
const fmt = (d: string | null | undefined) =>
  !d ? '—' : new Date(`${d}T12:00:00Z`).toLocaleDateString('en-GB',
    { day: '2-digit', month: 'short', year: 'numeric', timeZone: 'UTC' });

const UnlimitedStatus: React.FC<{ r: SummaryRow }> = ({ r }) => {
  if (r.unlimited_active > 0) {
    return (
      <>
        <span className="badge badge-success">Active</span>{' '}
        <span className="therapy-remaining-hint">
          to {fmt(r.current_unlimited_expiry)}
          {r.current_unlimited_days_remaining !== null &&
            <> · {r.current_unlimited_days_remaining} calendar days left</>}
        </span>
      </>
    );
  }
  if (r.unlimited_scheduled > 0) {
    return <><span className="badge badge-warning">Scheduled</span>{' '}
      <span className="therapy-remaining-hint">from {fmt(r.next_unlimited_start)}</span></>;
  }
  if (r.unlimited_pending > 0) return <span className="badge badge-muted">Unclaimed</span>;
  if (r.unlimited_finished > 0) return <span className="therapy-remaining-hint">Finished</span>;
  return <span className="therapy-remaining-hint">—</span>;
};

const Detail: React.FC<{ customerId: string }> = ({ customerId }) => {
  const [data, setData] = useState<any | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let live = true;
    (async () => {
      setLoading(true);
      const { data: d, error: e } = await supabase.rpc('therapy_customer_detail', { p_customer_id: customerId });
      if (!live) return;
      setLoading(false);
      if (e) { setError(e.message); return; }
      setError(null); setData(d);
    })();
    return () => { live = false; };
  }, [customerId]);

  if (loading) return <div className="therapy-detail">Loading…</div>;
  if (error) {
    return (
      <div className="therapy-detail">
        <div className="alert alert-danger" role="alert">
          This customer's detail could not be loaded: {error}
        </div>
      </div>
    );
  }
  if (!data) return null;

  const usable = (data.vouchers ?? []).filter((v: any) => v.remaining > 0 && !v.expired);
  const notUsable = (data.vouchers ?? []).filter((v: any) => v.remaining === 0 || v.expired);

  return (
    <div className="therapy-detail therapy-scope">
      <div className="therapy-detail-grid">
        <section>
          <h4 style={{ fontSize: 12.5, marginBottom: 6 }}>Usable now</h4>
          {usable.length === 0 && <p className="therapy-remaining-hint">Nothing currently usable.</p>}
          {usable.map((v: any, i: number) => (
            <div className="therapy-kv" key={`${v.voucher_id}-${v.source_ref ?? i}`}>
              <span className="k">
                {v.name} <span className="therapy-chip therapy-chip-source">{v.source}</span>
              </span>
              <span className="v">
                {v.remaining} {v.unit === 'session' ? 'session' : 'money'}
                {v.valid_until && <span className="therapy-remaining-hint"> · to {fmt(v.valid_until)}</span>}
              </span>
            </div>
          ))}
        </section>

        <section>
          <h4 style={{ fontSize: 12.5, marginBottom: 6 }}>Used, expired, revoked or refunded</h4>
          {notUsable.length === 0 && <p className="therapy-remaining-hint">Nothing.</p>}
          {notUsable.map((v: any, i: number) => (
            <div className="therapy-kv" key={`${v.voucher_id}-x-${v.source_ref ?? i}`}>
              <span className="k">{v.name} <span className="therapy-chip therapy-chip-source">{v.source}</span></span>
              <span className="v therapy-remaining-hint">
                {v.redeemed > 0 && <>{v.redeemed} used </>}
                {v.revoked > 0 && <>{v.revoked} revoked </>}
                {v.expired && <>expired {fmt(v.valid_until)}</>}
              </span>
            </div>
          ))}
        </section>
      </div>

      <h4 style={{ fontSize: 12.5, margin: '14px 0 6px' }}>Unlimited therapy</h4>
      {(data.unlimited ?? []).length === 0 && <p className="therapy-remaining-hint">None.</p>}
      {(data.unlimited ?? []).map((u: any) => (
        <div key={u.id} style={{ padding: '8px 0', borderTop: '1px solid var(--border)' }}>
          <div className="therapy-card-head">
            <div>
              <strong style={{ fontSize: 13 }}>{u.package_name}</strong>{' '}
              <span className="therapy-chip">{u.source}</span>{' '}
              <span className="therapy-chip">{u.status}</span>
            </div>
            <span className="therapy-remaining-hint">{u.entitlement_no}</span>
          </div>
          <div style={{ marginTop: 6 }}>
            <ExpiryExplanation data={u.explanation} coverage={u.coverage}
                               daysRemaining={u.calendar_days_remaining} />
          </div>
          {(u.adjustments ?? []).length > 0 && (
            <ul style={{ margin: '6px 0 0 18px', fontSize: 11.5, color: 'var(--text-muted)' }}>
              {u.adjustments.map((a: any, i: number) => (
                <li key={i}>
                  {new Date(a.at).toLocaleDateString('en-GB')} — {a.action.replace(/_/g, ' ')}
                  {a.old_expiry && a.new_expiry && <> · {fmt(a.old_expiry)} → {fmt(a.new_expiry)}</>}
                  {a.reason && <> · {a.reason}</>}
                </li>
              ))}
            </ul>
          )}
        </div>
      ))}

      {(data.pending ?? []).length > 0 && (
        <>
          <h4 style={{ fontSize: 12.5, margin: '14px 0 6px' }}>Unclaimed — not yet usable</h4>
          {data.pending.map((p: any, i: number) => (
            <div className="therapy-kv" key={i}>
              <span className="k">{p.entitlement_no} · {p.reward_kind}</span>
              <span className="v therapy-remaining-hint">claim by {fmt(p.deadline)}</span>
            </div>
          ))}
        </>
      )}

      {(data.redemptions ?? []).length > 0 && (
        <>
          <h4 style={{ fontSize: 12.5, margin: '14px 0 6px' }}>Redemption history</h4>
          <ul style={{ margin: '0 0 0 18px', fontSize: 11.5, color: 'var(--text-muted)' }}>
            {data.redemptions.slice(0, 12).map((r: any, i: number) => (
              <li key={i}>{new Date(r.at).toLocaleDateString('en-GB')} — {r.voucher}</li>
            ))}
          </ul>
        </>
      )}
    </div>
  );
};

export const CustomerTherapySummary: React.FC = () => {
  const [rows, setRows] = useState<SummaryRow[]>([]);
  const [total, setTotal] = useState(0);
  const [search, setSearch] = useState('');
  const [applied, setApplied] = useState('');
  const [onlyActive, setOnlyActive] = useState(false);
  const [page, setPage] = useState(0);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [expanded, setExpanded] = useState<string | null>(null);

  const load = useCallback(async () => {
    setLoading(true);
    const { data, error: e } = await supabase.rpc('therapy_customer_summary', {
      p_search: applied || null, p_limit: PAGE, p_offset: page * PAGE, p_only_active: onlyActive,
    });
    setLoading(false);
    if (e) { setError(e.message); setRows([]); setTotal(0); return; }
    setError(null);
    const list = (data as SummaryRow[]) ?? [];
    setRows(list);
    setTotal(list.length > 0 ? Number(list[0].total_customers) : 0);
  }, [applied, page, onlyActive]);

  useEffect(() => { void load(); }, [load]);

  const pages = Math.max(1, Math.ceil(total / PAGE));
  const needsReview = useMemo(() => rows.filter(r => r.needs_review).length, [rows]);

  return (
    <div className="therapy-scope">
      <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap', alignItems: 'flex-end', marginBottom: 10 }}>
        <div className="form-group" style={{ marginBottom: 0, flex: '1 1 220px', minWidth: 0 }}>
          <label htmlFor="therapy-search">Search customers</label>
          <input id="therapy-search" type="search" value={search} placeholder="Name or phone"
                 onChange={e => setSearch(e.target.value)}
                 onKeyDown={e => { if (e.key === 'Enter') { setPage(0); setApplied(search); } }} />
        </div>
        <button className="btn btn-secondary btn-sm" onClick={() => { setPage(0); setApplied(search); }}>
          <Search size={14} aria-hidden="true" /> Search
        </button>
        <label className="therapy-inline" style={{ fontSize: 12.5, alignItems: 'center' }}>
          <input type="checkbox" checked={onlyActive} onChange={e => { setPage(0); setOnlyActive(e.target.checked); }} />
          <span>Only customers with something usable</span>
        </label>
        <button className="btn btn-secondary btn-sm" onClick={() => void load()} disabled={loading}>
          <RefreshCw size={13} aria-hidden="true" /> {loading ? 'Loading…' : 'Refresh'}
        </button>
      </div>

      {error && (
        <div className="alert alert-danger" role="alert">
          Customer holdings could not be loaded: {error}
        </div>
      )}

      <p className="therapy-remaining-hint" aria-live="polite">
        {loading ? 'Loading…'
          : total === 0 ? 'No customers hold therapy benefits yet.'
          : `Showing ${rows.length} of ${total} customer${total === 1 ? '' : 's'}`}
        {needsReview > 0 && <> · <strong>{needsReview}</strong> on this page need a holiday country</>}
      </p>

      {/* Desktop */}
      <div className="table-wrap therapy-desktop-only">
        <table className="therapy-summary-table">
          <thead>
            <tr>
              <th scope="col">Customer</th>
              <th scope="col">Phone</th>
              <th scope="col" className="therapy-num">Therapy issued</th>
              <th scope="col" className="therapy-num">Used</th>
              <th scope="col" className="therapy-num">Remaining</th>
              <th scope="col" className="therapy-num">Money vouchers</th>
              <th scope="col">Unlimited therapy</th>
            </tr>
          </thead>
          <tbody>
            {rows.length === 0 && !loading && (
              <tr><td colSpan={7} style={{ textAlign: 'center', color: 'var(--text-muted)', padding: 24 }}>
                No customers match.
              </td></tr>
            )}
            {rows.map(r => (
              <React.Fragment key={r.customer_id}>
                <tr>
                  <td>
                    <button type="button" className="therapy-row-button"
                            aria-expanded={expanded === r.customer_id}
                            onClick={() => setExpanded(x => x === r.customer_id ? null : r.customer_id)}>
                      {expanded === r.customer_id
                        ? <ChevronDown size={14} aria-hidden="true" />
                        : <ChevronRight size={14} aria-hidden="true" />}
                      <strong>{r.customer_name}</strong>
                    </button>
                  </td>
                  <td style={{ fontSize: 12 }}>{r.customer_phone}</td>
                  <td className="therapy-num">{r.therapy_vouchers_issued}</td>
                  <td className="therapy-num">{r.therapy_vouchers_redeemed}</td>
                  <td className="therapy-num"><strong>{r.therapy_vouchers_remaining}</strong></td>
                  <td className="therapy-num">{r.money_vouchers_remaining}</td>
                  <td><UnlimitedStatus r={r} /></td>
                </tr>
                {expanded === r.customer_id && (
                  <tr><td colSpan={7} style={{ padding: 0 }}><Detail customerId={r.customer_id} /></td></tr>
                )}
              </React.Fragment>
            ))}
          </tbody>
        </table>
      </div>

      {/* Narrow screens: one card per customer, so nothing needs sideways scrolling. */}
      <div className="therapy-cards">
        {rows.map(r => (
          <div className="therapy-card" key={r.customer_id}>
            <div className="therapy-card-head">
              <div>
                <div className="therapy-card-name">{r.customer_name}</div>
                <div className="therapy-remaining-hint">{r.customer_phone}</div>
              </div>
            </div>
            <div className="therapy-card-stats">
              <span className="therapy-chip">{r.therapy_vouchers_remaining} therapy left</span>
              <span className="therapy-chip">{r.therapy_vouchers_redeemed} used</span>
              {r.money_vouchers_remaining > 0 && <span className="therapy-chip">{r.money_vouchers_remaining} money</span>}
              {r.needs_review && <span className="therapy-chip therapy-chip-warn">No holiday country</span>}
            </div>
            <div style={{ marginTop: 8 }}><UnlimitedStatus r={r} /></div>
            <button type="button" className="btn btn-secondary btn-sm" style={{ marginTop: 10 }}
                    aria-expanded={expanded === r.customer_id}
                    onClick={() => setExpanded(x => x === r.customer_id ? null : r.customer_id)}>
              {expanded === r.customer_id ? 'Hide details' : 'Show details'}
            </button>
            {expanded === r.customer_id && <Detail customerId={r.customer_id} />}
          </div>
        ))}
      </div>

      {pages > 1 && (
        <nav aria-label="Customer pages" style={{ display: 'flex', gap: 8, alignItems: 'center', marginTop: 12 }}>
          <button className="btn btn-secondary btn-sm" disabled={page === 0}
                  onClick={() => setPage(p => Math.max(0, p - 1))}>Previous</button>
          <span className="therapy-remaining-hint">Page {page + 1} of {pages}</span>
          <button className="btn btn-secondary btn-sm" disabled={page + 1 >= pages}
                  onClick={() => setPage(p => p + 1)}>Next</button>
        </nav>
      )}
    </div>
  );
};

export { CoverageNotice };
