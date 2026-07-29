import React, { useEffect, useMemo, useRef, useState } from 'react';
import { Search, ChevronDown, X } from 'lucide-react';
import { supabase } from '../lib/supabase';

export type SearchOption = {
  value: string;
  label: string;
  sublabel?: string;
  /** Everything this option should be findable by (name, SKU, code…). */
  search?: string;
  disabled?: boolean;
};

/**
 * A type-ahead replacement for a long <select>. Filters on the option's
 * `search` text (falling back to its label), so a product can be found by
 * name or SKU, a voucher by name or code, and so on.
 */
export const SearchSelect: React.FC<{
  options: SearchOption[];
  value: string;
  onChange: (value: string) => void;
  placeholder?: string;
  /** Values already chosen elsewhere; hidden from this list. */
  exclude?: string[];
  disabled?: boolean;
  emptyLabel?: string;
  style?: React.CSSProperties;
}> = ({ options, value, onChange, placeholder = 'Search…', exclude = [],
       disabled = false, emptyLabel = 'No matches', style }) => {
  const [open, setOpen] = useState(false);
  const [query, setQuery] = useState('');
  const boxRef = useRef<HTMLDivElement>(null);

  const selected = options.find(o => o.value === value) ?? null;

  useEffect(() => {
    const onDoc = (e: MouseEvent) => {
      if (boxRef.current && !boxRef.current.contains(e.target as Node)) { setOpen(false); setQuery(''); }
    };
    document.addEventListener('mousedown', onDoc);
    return () => document.removeEventListener('mousedown', onDoc);
  }, []);

  const visible = useMemo(() => {
    const q = query.trim().toLowerCase();
    return options
      .filter(o => o.value === value || !exclude.includes(o.value))
      .filter(o => !q || (o.search ?? o.label).toLowerCase().includes(q))
      .slice(0, 200);
  }, [options, query, exclude, value]);

  return (
    <div ref={boxRef} style={{ position: 'relative', ...style }}>
      <button type="button" disabled={disabled}
        onClick={() => { setOpen(o => !o); setQuery(''); }}
        style={{
          width: '100%', textAlign: 'left', background: 'var(--surface)',
          border: '1px solid var(--border)', borderRadius: 'var(--radius-sm)',
          padding: '8px 28px 8px 10px', fontSize: 13, cursor: disabled ? 'not-allowed' : 'pointer',
          color: selected ? 'var(--text)' : 'var(--text-muted)', position: 'relative',
          minHeight: 36, opacity: disabled ? 0.6 : 1,
        }}>
        {selected ? selected.label : placeholder}
        <ChevronDown size={14} style={{ position: 'absolute', right: 9, top: '50%', transform: 'translateY(-50%)', color: 'var(--text-muted)' }} />
      </button>

      {open && (
        <div style={{
          position: 'absolute', zIndex: 60, top: 'calc(100% + 3px)', left: 0, right: 0,
          background: 'var(--surface)', border: '1px solid var(--border)',
          borderRadius: 'var(--radius-sm)', boxShadow: 'var(--shadow-lg, 0 8px 24px rgba(0,0,0,.14))',
          maxHeight: 300, overflowY: 'auto',
        }}>
          <div style={{ position: 'sticky', top: 0, background: 'var(--surface)', padding: 7, borderBottom: '1px solid var(--border)' }}>
            <div style={{ position: 'relative' }}>
              <Search size={14} style={{ position: 'absolute', left: 9, top: 'calc(50% - 7px)', color: 'var(--text-muted)' }} />
              <input autoFocus value={query} onChange={e => setQuery(e.target.value)}
                placeholder={placeholder} style={{ paddingLeft: 30, fontSize: 12.5 }} />
            </div>
          </div>
          {value && (
            <div onClick={() => { onChange(''); setOpen(false); setQuery(''); }}
              style={{ padding: '7px 10px', fontSize: 12.5, color: 'var(--text-muted)', cursor: 'pointer', display: 'flex', gap: 6, alignItems: 'center' }}>
              <X size={12} /> Clear selection
            </div>
          )}
          {visible.length === 0 && (
            <div style={{ padding: '10px', fontSize: 12.5, color: 'var(--text-muted)' }}>{emptyLabel}</div>
          )}
          {visible.map(o => (
            <div key={o.value}
              onClick={() => { if (o.disabled) return; onChange(o.value); setOpen(false); setQuery(''); }}
              style={{
                padding: '7px 10px', fontSize: 12.5, cursor: o.disabled ? 'not-allowed' : 'pointer',
                background: o.value === value ? 'var(--primary-light)' : 'transparent',
                opacity: o.disabled ? 0.45 : 1,
                borderBottom: '1px solid var(--border)',
              }}>
              <div>{o.label}</div>
              {o.sublabel && <div style={{ fontSize: 11, color: 'var(--text-muted)' }}>{o.sublabel}</div>}
            </div>
          ))}
        </div>
      )}
    </div>
  );
};

/**
 * Customer picker that searches on the SERVER. The customer table is far too
 * large to load into the browser, so this queries by name, phone, email and
 * the legacy customer id held in notes, returning the closest matches.
 */
export const CustomerSearchSelect: React.FC<{
  value: string;
  onChange: (id: string) => void;
  placeholder?: string;
  disabled?: boolean;
}> = ({ value, onChange, placeholder = 'Search name, ID, phone or email…', disabled = false }) => {
  const [open, setOpen] = useState(false);
  const [query, setQuery] = useState('');
  const [rows, setRows] = useState<any[]>([]);
  const [busy, setBusy] = useState(false);
  const [selected, setSelected] = useState<any | null>(null);
  const boxRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const onDoc = (e: MouseEvent) => {
      if (boxRef.current && !boxRef.current.contains(e.target as Node)) setOpen(false);
    };
    document.addEventListener('mousedown', onDoc);
    return () => document.removeEventListener('mousedown', onDoc);
  }, []);

  // Keep the label for an already-chosen customer.
  useEffect(() => {
    if (!value) { setSelected(null); return; }
    if (selected?.id === value) return;
    supabase.from('customers').select('id, full_name, phone, email, notes').eq('id', value).maybeSingle()
      .then(({ data }) => setSelected(data ?? null));
  }, [value]);

  // Debounced server search.
  useEffect(() => {
    if (!open) return;
    const handle = setTimeout(async () => {
      setBusy(true);
      const raw = query.trim().replace(/[,()]/g, ' ');
      let q = supabase.from('customers').select('id, full_name, phone, email, notes')
        .is('deleted_at', null).order('full_name').limit(50);
      if (raw) {
        const like = `%${raw}%`;
        q = q.or(`full_name.ilike.${like},phone.ilike.${like},email.ilike.${like},notes.ilike.${like}`);
      }
      const { data } = await q;
      setRows((data as any[]) ?? []);
      setBusy(false);
    }, 220);
    return () => clearTimeout(handle);
  }, [query, open]);

  const label = selected
    ? `${selected.full_name}${selected.phone ? ` (${selected.phone})` : ''}`
    : placeholder;

  return (
    <div ref={boxRef} style={{ position: 'relative' }}>
      <button type="button" disabled={disabled} onClick={() => { setOpen(o => !o); setQuery(''); }}
        style={{
          width: '100%', textAlign: 'left', background: 'var(--surface)',
          border: '1px solid var(--border)', borderRadius: 'var(--radius-sm)',
          padding: '8px 28px 8px 10px', fontSize: 13, cursor: disabled ? 'not-allowed' : 'pointer',
          color: selected ? 'var(--text)' : 'var(--text-muted)', minHeight: 36, opacity: disabled ? 0.6 : 1,
        }}>
        {label}
        <ChevronDown size={14} style={{ position: 'absolute', right: 9, top: '50%', transform: 'translateY(-50%)', color: 'var(--text-muted)' }} />
      </button>

      {open && (
        <div style={{
          position: 'absolute', zIndex: 60, top: 'calc(100% + 3px)', left: 0, right: 0,
          background: 'var(--surface)', border: '1px solid var(--border)',
          borderRadius: 'var(--radius-sm)', boxShadow: 'var(--shadow-lg, 0 8px 24px rgba(0,0,0,.14))',
          maxHeight: 320, overflowY: 'auto',
        }}>
          <div style={{ position: 'sticky', top: 0, background: 'var(--surface)', padding: 7, borderBottom: '1px solid var(--border)' }}>
            <div style={{ position: 'relative' }}>
              <Search size={14} style={{ position: 'absolute', left: 9, top: 'calc(50% - 7px)', color: 'var(--text-muted)' }} />
              <input autoFocus value={query} onChange={e => setQuery(e.target.value)}
                placeholder={placeholder} style={{ paddingLeft: 30, fontSize: 12.5 }} />
            </div>
          </div>
          {busy && <div style={{ padding: 10, fontSize: 12.5, color: 'var(--text-muted)' }}>Searching…</div>}
          {!busy && rows.length === 0 && (
            <div style={{ padding: 10, fontSize: 12.5, color: 'var(--text-muted)' }}>No matching customer</div>
          )}
          {rows.map(c => (
            <div key={c.id} onClick={() => { onChange(c.id); setSelected(c); setOpen(false); }}
              style={{
                padding: '7px 10px', fontSize: 12.5, cursor: 'pointer',
                background: c.id === value ? 'var(--primary-light)' : 'transparent',
                borderBottom: '1px solid var(--border)',
              }}>
              <div style={{ fontWeight: 600 }}>{c.full_name}</div>
              <div style={{ fontSize: 11, color: 'var(--text-muted)' }}>
                {[c.phone, c.email].filter(Boolean).join(' · ')}
                {c.notes && /CUST-\d+/i.test(c.notes) ? ` · ${(c.notes.match(/CUST-\d+/i) || [])[0]}` : ''}
              </div>
            </div>
          ))}
          {!busy && rows.length >= 50 && (
            <div style={{ padding: '7px 10px', fontSize: 11, color: 'var(--text-muted)' }}>
              Showing the first 50 matches — keep typing to narrow them down.
            </div>
          )}
        </div>
      )}
    </div>
  );
};

export default SearchSelect;
