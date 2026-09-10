import React, { useEffect, useRef, useState } from 'react';
import { supabase } from '../../lib/supabase';
export type StockOption = { value: string; label: string };
export function StockHistoryFilter({ kind, label, selected, onChange }: { kind: string; label: string; selected: StockOption[]; onChange: (options: StockOption[]) => void }) {
  const [open, setOpen] = useState(false), [query, setQuery] = useState('');
  const [options, setOptions] = useState<StockOption[]>([]), [offset, setOffset] = useState(0), [total, setTotal] = useState(0);
  const [busy, setBusy] = useState(false), [error, setError] = useState('');
  const trigger = useRef<HTMLButtonElement>(null);
  const close = () => { setOpen(false); trigger.current?.focus(); };
  useEffect(() => {
    if (!open) return;
    let live = true;
    setBusy(true); setError('');
    const timer = setTimeout(async () => {
      const { data, error } = await supabase.rpc('stock_history_options', { p_kind: kind, p_query: query, p_offset: offset });
      if (!live) return;
      if (error) { setError('Could not load choices. Close and reopen to retry.'); setOptions([]); }
      else { setOptions(old => offset ? [...old, ...(data.rows || [])] : data.rows || []); setTotal(data.total); }
      setBusy(false);
    }, 180);
    return () => { live = false; clearTimeout(timer); };
  }, [open, query, offset, kind]);
  return <div className="stock-filter">
    <button ref={trigger} className="btn btn-secondary" aria-expanded={open} aria-controls={`stock-options-${kind}`} onClick={() => { setOffset(0); setOptions([]); setOpen(!open); }}>{label}{selected.length ? ` (${selected.length})` : ''}</button>
    {open && <div id={`stock-options-${kind}`} className="stock-filter-options" onKeyDown={e => { if (e.key === 'Escape') { e.stopPropagation(); close(); } }}>
      <label>Search {label.toLowerCase()}<input autoFocus value={query} onChange={e => { setQuery(e.target.value); setOffset(0); }} /></label>
      {error && <p role="alert">{error}</p>}
      <div className="stock-option-list" aria-busy={busy}>
        {options.map(o => <label key={o.value}><input type="checkbox" checked={selected.some(s => s.value === o.value)} onChange={e => onChange(e.target.checked ? [...selected, o] : selected.filter(s => s.value !== o.value))} /><span>{o.label}</span></label>)}
        {!busy && !options.length && !error && <p>No permitted choices match.</p>}
      </div>
      {busy && <p role="status">Loading choices…</p>}
      {!busy && options.length < total && <button className="btn btn-secondary" onClick={() => setOffset(options.length)}>More choices</button>}
      <button className="btn btn-secondary" onClick={close}>Done</button>
    </div>}
    <div className="stock-chips">{selected.map(o => <button key={o.value} className="stock-chip" aria-label={`Remove ${o.label} from ${label}`} onClick={() => onChange(selected.filter(s => s.value !== o.value))}>{o.label} <span aria-hidden>×</span></button>)}</div>
  </div>;
}
