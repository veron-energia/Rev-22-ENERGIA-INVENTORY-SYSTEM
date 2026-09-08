import React, { useCallback, useEffect, useMemo, useState } from 'react';
import { AlertTriangle, RefreshCw } from 'lucide-react';
import { supabase } from '../../lib/supabase';
import { periodLabel, settlementPeriod, toIsoDate } from '../../lib/tiktok/settlementPeriod.mjs';

/**
 * TikTok settlement figures for one reporting month.
 *
 * Shared by the import page and the TikTok report so the two cannot drift: both
 * read the same `tiktok_settlement_totals`, which applies the same period rule
 * and the same classification as `lib/tiktok/*`. A database test asserts the SQL
 * and the JavaScript agree.
 *
 * The five figures are:
 *
 *   Revenue     after seller discounts and customer refunds, before fees
 *   Fee         net transaction fees, excluding refunds and operating expenses
 *   Settlement  Revenue − Fee, BEFORE operating expenses
 *   Expense     advertising and operating payments, net of reversals
 *   Income      Settlement − Expense
 *
 * "Settlement" here is deliberately not TikTok's own settlement figure, which
 * already has advertising deducted. Both are shown, labelled, so they can be
 * compared rather than mistaken for each other — and TikTok's is labelled as the
 * imported source total, not as cash received, because withdrawals to a bank
 * happen separately.
 */

export interface SettlementTotals {
  year: number; month: number;
  period_start: string; period_end: string; timezone: string;
  row_count: number;
  revenue: number; fee: number; settlement: number; expense: number; income: number;
  tiktok_net_settlement: number;
  by_category: Record<string, number>;
  unknown_count: number; balance_movement_count: number; pending_match_count: number;
  currency_count: number; undated_count: number; needs_review: boolean;
}

const money = (n: number) => `S$${Number(n ?? 0).toFixed(2)}`;
const MONTHS = ['January','February','March','April','May','June','July','August','September','October','November','December'];

/** The Singapore reporting month "now", so the default is not the browser's month. */
export function currentSgtMonth(): { year: number; month: number } {
  const parts = new Intl.DateTimeFormat('en-GB', {
    timeZone: 'Asia/Singapore', year: 'numeric', month: '2-digit',
  }).formatToParts(new Date());
  const get = (t: string) => Number(parts.find(p => p.type === t)?.value);
  return { year: get('year'), month: get('month') };
}

export const MonthPicker: React.FC<{
  year: number; month: number;
  onChange: (year: number, month: number) => void;
}> = ({ year, month, onChange }) => {
  const now = currentSgtMonth();
  const years = Array.from({ length: 6 }, (_, i) => now.year - 4 + i);
  return (
    <div style={{ display: 'flex', gap: 8, alignItems: 'flex-end', flexWrap: 'wrap' }}>
      <div className="form-group" style={{ marginBottom: 0 }}>
        <label>Reporting month</label>
        <select value={month} onChange={e => onChange(year, Number(e.target.value))}>
          {MONTHS.map((m, i) => <option key={m} value={i + 1}>{m}</option>)}
        </select>
      </div>
      <div className="form-group" style={{ marginBottom: 0 }}>
        <label>Year</label>
        <select value={year} onChange={e => onChange(Number(e.target.value), month)}>
          {years.map(y => <option key={y} value={y}>{y}</option>)}
        </select>
      </div>
    </div>
  );
};

/** The exact range a reporting month covers, always stated with its timezone. */
export const PeriodBanner: React.FC<{ year: number; month: number; rowCount?: number }> = ({ year, month, rowCount }) => {
  const p = settlementPeriod(year, month);
  return (
    <div style={{ fontSize: 12.5, color: 'var(--text-secondary)', marginTop: 6 }}>
      <strong>{MONTHS[month - 1]} {year}</strong> settlement period:{' '}
      <strong>{periodLabel(year, month)}</strong>
      <span style={{ color: 'var(--text-muted)' }}>
        {' '}({toIsoDate(p.start)} to {toIsoDate(p.end)}, both inclusive)
      </span>
      {rowCount !== undefined && (
        <span style={{ color: 'var(--text-muted)' }}> · {rowCount} settled transaction{rowCount === 1 ? '' : 's'} imported</span>
      )}
    </div>
  );
};

const Card: React.FC<{ label: string; value: string; hint: string; tone?: 'cost' | 'net' }> =
  ({ label, value, hint, tone }) => (
  <div className="card" style={{ padding: 14, flex: '1 1 170px', minWidth: 170 }}>
    <div style={{ fontSize: 11.5, color: 'var(--text-muted)', textTransform: 'uppercase', letterSpacing: .3 }}>{label}</div>
    <div style={{ fontSize: 20, fontWeight: 700, marginTop: 4,
                  color: tone === 'cost' ? 'var(--danger)' : tone === 'net' ? 'var(--primary)' : 'var(--text)' }}>
      {value}
    </div>
    <div style={{ fontSize: 11, color: 'var(--text-muted)', marginTop: 4, lineHeight: 1.45 }}>{hint}</div>
  </div>
);

export const SettlementCards: React.FC<{ t: SettlementTotals }> = ({ t }) => (
  <div style={{ display: 'flex', gap: 10, flexWrap: 'wrap', marginTop: 12 }}>
    <Card label="Total Revenue" value={money(t.revenue)}
      hint="After seller discounts and customer refunds, before fees and expenses." />
    <Card label="Total Fee" value={money(t.fee)} tone="cost"
      hint="Net transaction fees. Excludes customer refunds and operating expenses." />
    <Card label="Total Settlement" value={money(t.settlement)}
      hint="Revenue less fees, before operating expenses." />
    <Card label="Total Expense" value={money(t.expense)} tone="cost"
      hint="Advertising and operating payments, net of reversals." />
    <Card label="Total Income" value={money(t.income)} tone="net"
      hint="Settlement less expenses." />
  </div>
);

/**
 * Everything that stops a figure being taken at face value: rows that could not
 * be placed, types nobody has classified, more than one currency, and the fact
 * that an open month only reflects what has been imported so far.
 */
export const SettlementNotices: React.FC<{ t: SettlementTotals; isOpenPeriod: boolean }> = ({ t, isOpenPeriod }) => {
  const notices: string[] = [];
  if (t.undated_count > 0) {
    notices.push(`${t.undated_count} imported transaction(s) have no usable settled date and are in no period at all. `
      + `These totals are incomplete until those are corrected.`);
  }
  if (t.unknown_count > 0) {
    notices.push(`${t.unknown_count} transaction(s) have a type that is not yet classified. `
      + `They contribute nothing to the figures above and need review.`);
  }
  if (t.currency_count > 1) {
    notices.push(`${t.currency_count} currencies are present. These figures add different currencies together `
      + `and should not be read as a single total until a conversion is agreed.`);
  }
  if (t.balance_movement_count > 0) {
    notices.push(`${t.balance_movement_count} balance movement(s) (withdrawals, transfers, reserves) are excluded `
      + `on purpose: they move money that the transactions above already account for.`);
  }
  if (notices.length === 0 && !isOpenPeriod) return null;

  return (
    <div style={{ marginTop: 12 }}>
      {isOpenPeriod && (
        <div className="alert alert-info" style={{ marginBottom: notices.length ? 8 : 0 }}>
          <span>ℹ️</span>
          <div>
            This period has not finished yet. The figures reflect the transactions imported so far —
            not a complete month. Missing days are missing, not zero.
          </div>
        </div>
      )}
      {notices.map((n, i) => (
        <div key={i} className="alert alert-danger" style={{ marginBottom: i === notices.length - 1 ? 0 : 8 }}>
          <AlertTriangle size={15} />
          <div>{n}</div>
        </div>
      ))}
    </div>
  );
};

/** Our figures beside TikTok's own, so the difference is explained rather than hidden. */
export const ReconciliationPanel: React.FC<{ t: SettlementTotals }> = ({ t }) => {
  const diff = Number((t.income - t.tiktok_net_settlement).toFixed(2));
  return (
    <div className="card" style={{ padding: 14, marginTop: 12 }}>
      <h4 style={{ fontSize: 13.5, fontWeight: 700, marginBottom: 8 }}>Reconciliation</h4>
      <div className="affiliate-kv"><span className="k">Total Settlement (ours)</span>
        <span className="v">{money(t.settlement)} — revenue less fees, before expenses</span></div>
      <div className="affiliate-kv"><span className="k">Total Income (ours)</span>
        <span className="v">{money(t.income)} — settlement less expenses</span></div>
      <div className="affiliate-kv"><span className="k">TikTok reported net settlement</span>
        <span className="v">{money(t.tiktok_net_settlement)} — imported source total, used for reconciliation</span></div>
      <div className="affiliate-kv"><span className="k">Difference (Income − TikTok)</span>
        <span className="v" style={{ color: diff === 0 ? 'var(--success)' : 'var(--warning, #b45309)' }}>
          {money(diff)}
          {diff === 0
            ? ' — these agree for this period.'
            : ' — identify the transfers, reserves or financing behind this before relying on it.'}
        </span></div>
      <p style={{ fontSize: 11.5, color: 'var(--text-muted)', marginTop: 8, lineHeight: 1.5 }}>
        TikTok's settlement figure already has advertising deducted, so it is expected to differ from
        <strong> Total Settlement</strong> and to agree with <strong>Total Income</strong>. None of these is
        cash in the bank — withdrawals happen separately and are listed on their own sheet.
      </p>
    </div>
  );
};

/** Loads the totals for a month and store. Returns null while loading. */
export function useSettlementTotals(year: number, month: number, storeId: string | null) {
  const [totals, setTotals] = useState<SettlementTotals | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  const load = useCallback(async () => {
    setLoading(true); setError(null);
    const { data, error } = await supabase.rpc('tiktok_settlement_totals', {
      p_year: year, p_month: month, p_store_id: storeId || null,
    });
    setLoading(false);
    if (error) { setError(error.message); setTotals(null); return; }
    setTotals(data as SettlementTotals);
  }, [year, month, storeId]);

  useEffect(() => { void load(); }, [load]);
  return { totals, error, loading, reload: load };
}

/** The whole block: picker, period, cards, notices, reconciliation. */
export const SettlementSummary: React.FC<{
  storeId: string | null;
  year: number; month: number;
  onChangeMonth: (year: number, month: number) => void;
  showPicker?: boolean;
}> = ({ storeId, year, month, onChangeMonth, showPicker = true }) => {
  const { totals, error, loading, reload } = useSettlementTotals(year, month, storeId);
  const isOpenPeriod = useMemo(() => {
    const now = currentSgtMonth();
    const end = settlementPeriod(year, month).end;
    const today = new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Singapore' }).format(new Date());
    return today <= toIsoDate(end) || (year === now.year && month === now.month);
  }, [year, month]);

  return (
    <div>
      <div style={{ display: 'flex', gap: 10, alignItems: 'flex-end', flexWrap: 'wrap' }}>
        {showPicker && <MonthPicker year={year} month={month} onChange={onChangeMonth} />}
        <button className="btn btn-secondary btn-sm" onClick={() => void reload()} disabled={loading}>
          <RefreshCw size={13} /> {loading ? 'Loading…' : 'Refresh'}
        </button>
      </div>
      <PeriodBanner year={year} month={month} rowCount={totals?.row_count} />
      {error && <div className="alert alert-danger" style={{ marginTop: 10 }}><span>⚠</span><div>{error}</div></div>}
      {totals && (
        <>
          <SettlementCards t={totals} />
          <SettlementNotices t={totals} isOpenPeriod={isOpenPeriod} />
          <ReconciliationPanel t={totals} />
        </>
      )}
    </div>
  );
};
