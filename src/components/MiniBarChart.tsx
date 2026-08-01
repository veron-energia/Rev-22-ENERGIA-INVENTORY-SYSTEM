import React from 'react';

/**
 * A small horizontal bar chart drawn as inline SVG.
 *
 * Deliberately not a charting library: the reports need one simple comparison
 * chart, and adding recharts (~500 KB) for that would cost more than it gives.
 */

export interface BarDatum {
  label: string;
  value: number;
  /** Optional second line under the label. */
  sub?: string;
}

export const MiniBarChart: React.FC<{
  data: BarDatum[];
  /** Formats the value shown at the end of each bar. */
  format?: (n: number) => string;
  /** Show at most this many bars, largest first. */
  limit?: number;
  title?: string;
  emptyText?: string;
}> = ({ data, format = (n) => n.toLocaleString(), limit = 10, title, emptyText = 'No data to chart' }) => {
  const top = [...data]
    .filter(d => Number.isFinite(d.value))
    .sort((a, b) => b.value - a.value)
    .slice(0, limit);
  const max = top.reduce((m, d) => Math.max(m, Math.abs(d.value)), 0);

  if (top.length === 0 || max === 0) {
    return (
      <div style={{ padding: '18px 12px', fontSize: 12.5, color: 'var(--text-muted)', textAlign: 'center' }}>
        {emptyText}
      </div>
    );
  }

  return (
    <div style={{ padding: '10px 12px 14px' }}>
      {title && <div style={{ fontSize: 12.5, fontWeight: 700, marginBottom: 8 }}>{title}</div>}
      <div style={{ display: 'flex', flexDirection: 'column', gap: 7 }}>
        {top.map((d, i) => {
          const pct = max > 0 ? Math.max((Math.abs(d.value) / max) * 100, 1) : 0;
          return (
            <div key={`${d.label}-${i}`} style={{ display: 'grid', gridTemplateColumns: '150px 1fr 92px', gap: 10, alignItems: 'center' }}>
              <div style={{ fontSize: 12, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }} title={d.label}>
                {d.label}
                {d.sub && <div style={{ fontSize: 10.5, color: 'var(--text-muted)' }}>{d.sub}</div>}
              </div>
              <div style={{ background: 'var(--bg)', borderRadius: 3, height: 16, overflow: 'hidden' }}>
                <div style={{
                  width: `${pct}%`, height: '100%',
                  background: d.value < 0 ? 'var(--danger)' : 'var(--primary)',
                  borderRadius: 3, transition: 'width .2s',
                }} />
              </div>
              <div style={{ fontSize: 12, textAlign: 'right', fontWeight: 600 }}>{format(d.value)}</div>
            </div>
          );
        })}
      </div>
      {data.length > limit && (
        <div style={{ fontSize: 11, color: 'var(--text-muted)', marginTop: 8 }}>
          Showing the top {limit} of {data.length}. The table below has them all.
        </div>
      )}
    </div>
  );
};

export default MiniBarChart;
