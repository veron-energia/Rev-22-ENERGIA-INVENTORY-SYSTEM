import React, { useId, useMemo, useState } from 'react';

type Option = { value: string; label: string; disabled?: boolean };
/** Invoice-specific, keyboard-operable search. Results stay in document flow so
 * the invoice modal scrolls to them instead of clipping an absolute popup. */
export function InvoiceSearchSelect({ options, value, onChange, label = 'Payment method' }: {
  options: Option[]; value: string; onChange: (value: string) => void; label?: string;
}) {
  const id = useId();
  const [open, setOpen] = useState(false);
  const [query, setQuery] = useState('');
  const [active, setActive] = useState(0);
  const visible = useMemo(() => options.filter(o => o.label.toLocaleLowerCase().includes(query.trim().toLocaleLowerCase())), [options, query]);
  const choose = (o: Option) => { if (!o.disabled) { onChange(o.value); setOpen(false); setQuery(''); } };
  return <div className="invoice-search-select">
    <button type="button" aria-label={label} aria-expanded={open} aria-controls={id}
      onClick={() => { setOpen(!open); setQuery(''); setActive(0); }}>
      {options.find(o => o.value === value)?.label || `Choose ${label.toLowerCase()}`} ▾
    </button>
    {open && <div className="invoice-search-results">
      <input autoFocus role="combobox" aria-label={`Search ${label.toLowerCase()}`} aria-controls={id}
        aria-expanded={open} aria-autocomplete="list" aria-activedescendant={visible[active] ? `${id}-${active}` : undefined}
        value={query} placeholder={`Search ${label.toLowerCase()}…`}
        onChange={e => { setQuery(e.target.value); setActive(0); }}
        onKeyDown={e => {
          if (e.key === 'Escape') { e.preventDefault(); e.stopPropagation(); setOpen(false); }
          if (e.key === 'ArrowDown') { e.preventDefault(); setActive(n => Math.min(n + 1, visible.length - 1)); }
          if (e.key === 'ArrowUp') { e.preventDefault(); setActive(n => Math.max(0, n - 1)); }
          if (e.key === 'Enter' && visible[active]) { e.preventDefault(); choose(visible[active]); }
        }} />
      <div id={id} role="listbox" aria-label={label}>
        {visible.map((o, i) => <button key={o.value} id={`${id}-${i}`} type="button" role="option"
          aria-selected={o.value === value} disabled={o.disabled} data-active={i === active}
          onClick={() => choose(o)}>{o.label}</button>)}
        {!visible.length && <p role="status">No matches found</p>}
      </div>
    </div>}
  </div>;
}
