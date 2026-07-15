import React, { useMemo, useRef, useState, useEffect } from 'react';
import { Customer } from '../types';
import { Search, X, Check } from 'lucide-react';

// Type-ahead customer picker. Searches name, phone and email.
// An optional `pinnedId` (e.g. the buyer on the invoice) is always shown
// first and highlighted, so the common case is one click.
const CustomerPicker: React.FC<{
  customers: Customer[];
  value: string;
  onChange: (id: string) => void;
  pinnedId?: string;
  pinnedNote?: string;
  excludeId?: string;
  placeholder?: string;
}> = ({ customers, value, onChange, pinnedId, pinnedNote = 'buyer on the invoice', excludeId, placeholder = 'Search name, phone or email…' }) => {
  const [query, setQuery] = useState('');
  const [open, setOpen] = useState(false);
  const boxRef = useRef<HTMLDivElement>(null);

  const selected = customers.find(c => c.id === value) ?? null;

  useEffect(() => {
    const onDoc = (ev: MouseEvent) => {
      if (boxRef.current && !boxRef.current.contains(ev.target as Node)) setOpen(false);
    };
    document.addEventListener('mousedown', onDoc);
    return () => document.removeEventListener('mousedown', onDoc);
  }, []);

  const results = useMemo(() => {
    const q = query.trim().toLowerCase();
    let list = customers.filter(c => c.id !== excludeId);
    if (q) {
      list = list.filter(c =>
        c.full_name.toLowerCase().includes(q) ||
        c.phone.toLowerCase().includes(q) ||
        (c.email ?? '').toLowerCase().includes(q));
    }
    // Pinned (buyer) first when it survives the filter.
    const pin = list.find(c => c.id === pinnedId);
    return pin ? [pin, ...list.filter(c => c.id !== pinnedId)] : list;
  }, [customers, query, pinnedId, excludeId]);

  const pick = (id: string) => { onChange(id); setQuery(''); setOpen(false); };

  return (
    <div ref={boxRef} style={{ position: 'relative' }}>
      {selected && !open ? (
        <div style={{ display: 'flex', alignItems: 'center', gap: 8, border: '1px solid var(--border)', borderRadius: 'var(--radius-sm)', padding: '8px 10px', background: 'var(--surface)' }}>
          <div style={{ flex: 1, fontSize: 13 }}>
            <strong>{selected.full_name}</strong>
            <span style={{ color: 'var(--text-muted)' }}> · {selected.phone}{selected.email ? ` · ${selected.email}` : ''}</span>
            {selected.id === pinnedId && <span className="badge badge-primary" style={{ marginLeft: 6, fontSize: 10 }}>{pinnedNote}</span>}
          </div>
          <button type="button" className="btn btn-secondary btn-sm" onClick={() => { setOpen(true); setQuery(''); }}>Change</button>
        </div>
      ) : (
        <div style={{ position: 'relative' }}>
          <Search size={14} style={{ position: 'absolute', left: 10, top: '50%', transform: 'translateY(-50%)', color: 'var(--text-muted)' }} />
          <input
            autoFocus={open}
            value={query}
            placeholder={placeholder}
            onChange={e => { setQuery(e.target.value); setOpen(true); }}
            onFocus={() => setOpen(true)}
            style={{ paddingLeft: 30, paddingRight: selected ? 30 : 10 }}
          />
          {selected && (
            <button type="button" className="btn btn-secondary btn-sm btn-icon"
              style={{ position: 'absolute', right: 4, top: '50%', transform: 'translateY(-50%)' }}
              onClick={() => { setOpen(false); setQuery(''); }}><X size={12} /></button>
          )}
        </div>
      )}

      {open && (
        <div style={{
          position: 'absolute', top: '100%', left: 0, right: 0, marginTop: 4, zIndex: 30,
          background: 'var(--surface)', border: '1px solid var(--border)', borderRadius: 'var(--radius-sm)',
          boxShadow: 'var(--shadow-md)', maxHeight: 220, overflowY: 'auto',
        }}>
          {results.length === 0 && <div style={{ padding: 10, fontSize: 12.5, color: 'var(--text-muted)' }}>No customer matches “{query}”.</div>}
          {results.map(c => (
            <button key={c.id} type="button" onClick={() => pick(c.id)}
              style={{
                display: 'flex', alignItems: 'center', gap: 8, width: '100%', textAlign: 'left',
                padding: '8px 10px', background: c.id === value ? 'var(--surface-2)' : 'none',
                border: 'none', borderBottom: '1px solid var(--border)', cursor: 'pointer', fontSize: 13,
              }}>
              {c.id === value ? <Check size={13} color="var(--primary)" /> : <span style={{ width: 13 }} />}
              <span style={{ flex: 1 }}>
                <strong>{c.full_name}</strong>
                {c.id === pinnedId && <span className="badge badge-primary" style={{ marginLeft: 6, fontSize: 10 }}>{pinnedNote}</span>}
                <div style={{ color: 'var(--text-muted)', fontSize: 11.5 }}>{c.phone}{c.email ? ` · ${c.email}` : ''}</div>
              </span>
            </button>
          ))}
        </div>
      )}
    </div>
  );
};

export default CustomerPicker;
