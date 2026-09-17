import React from 'react';
import { InvoiceSearchSelect } from './InvoiceSearchSelect';
import type { InstalmentDetails } from '../../lib/invoices/business';
export function InstalmentFields({ value, onChange, methods }: {
  value: InstalmentDetails; onChange: (value: InstalmentDetails) => void;
  methods: { id: string; name: string; is_wallet_credit?: boolean; is_active?: boolean; deleted_at?: string | null }[];
}) {
  return <fieldset style={{ minWidth: 0, border: '1px solid var(--border)', borderRadius: 8, padding: 12 }}>
    <legend>Instalment</legend>
    <label><input type="checkbox" style={{ width: 'auto' }} checked={!!value.instalment_category}
      onChange={e => onChange(e.target.checked ? { instalment_category: 'in_house', instalment_method_id: '', instalment_months: 3 }
        : { instalment_category: '', instalment_method_id: '', instalment_months: '' })} /> Instalments</label>
    {!!value.instalment_category && <div className="form-grid" style={{ marginTop: 8 }}>
      {/* No category: every instalment these screens record is in-house. The
          column keeps provider_funded for the rows already saved with it. */}
      <InvoiceSearchSelect label="Instalment payment method" value={value.instalment_method_id}
        onChange={id => onChange({ ...value, instalment_method_id: id })}
        options={methods.filter(m => !m.is_wallet_credit && m.is_active !== false && !m.deleted_at).map(m => ({ value: m.id, label: m.name }))} />
      <label>Duration (months)<input type="number" min={1} step={1} value={value.instalment_months}
        onChange={e => onChange({ ...value, instalment_months: e.target.value === '' ? '' : Number(e.target.value) })} /></label>
      <div style={{ display: 'flex', flexWrap: 'wrap', gap: 6 }}>{[3, 6, 9, 12].map(n => <button type="button" className="btn btn-secondary" key={n} onClick={() => onChange({ ...value, instalment_months: n })}>{n} months</button>)}</div>
      <p style={{ fontSize: 12 }}>These are the terms the invoice was paid under. The money itself is recorded as a payment, under the method above.</p>
    </div>}
  </fieldset>;
}
