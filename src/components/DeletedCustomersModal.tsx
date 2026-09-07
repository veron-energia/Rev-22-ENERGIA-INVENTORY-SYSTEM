import React, { useEffect, useState } from 'react';
import { supabase } from '../lib/supabase';
import { Modal } from './ui';
import PhoneInput, { isPhoneValid } from './PhoneInput';
import { inspectPhone, phoneErrorMessage } from '../lib/customer-phones/normalize.mjs';

type DeletedCustomer = { id: string; full_name: string; phone: string; total_count: number };
export default function DeletedCustomersModal({ onClose, onRestored }: { onClose: () => void; onRestored: () => void }) {
  const [query, setQuery] = useState('');
  const [page, setPage] = useState(0);
  const [rows, setRows] = useState<DeletedCustomer[]>([]);
  const [selected, setSelected] = useState<DeletedCustomer | null>(null);
  const [phone, setPhone] = useState('');
  const [reason, setReason] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [revision, setRevision] = useState(0);
  useEffect(() => {
    let active = true;
    const timeout = setTimeout(async () => {
      const res = await supabase.rpc('list_deleted_customers', { p_query: query || null, p_offset: page * 50 });
      if (!active) return;
      setError(res.error?.message ?? null);
      setRows(res.data?.rows ?? []);
    }, 250);
    return () => { active = false; clearTimeout(timeout); };
  }, [query, page, revision]);
  const restore = async () => {
    if (!selected) return;
    if (!isPhoneValid(phone)) { setError('Confirm the country and enter a valid phone number before restoring.'); return; }
    if (phone !== selected.phone && !reason.trim()) { setError('Give a reason for the replacement phone number.'); return; }
    setBusy(true); setError(null);
    const res = await supabase.rpc('restore_customer_with_phone', {
      p_customer_id: selected.id, p_new_phone: phone, p_reason: reason.trim() || null,
    });
    setBusy(false);
    if (res.error) { setError(phoneErrorMessage(res.error.message)); return; }
    setSelected(null); setRevision(n => n + 1); onRestored();
  };
  return <Modal title="Restore deleted customer" onClose={onClose}>
    <p>Restoring keeps the same customer ID, invoices and history. A phone number can belong to up to 3 non-deleted customers, including inactive customers.</p>
    {error && <div className="alert alert-danger" role="alert">{error}</div>}
    {selected ? <>
      <p><strong>{selected.full_name}</strong><br />Customer ID: {selected.id}<br />Stored phone: {selected.phone}</p>
      <div className="form-group"><label>Phone to use when restored</label><PhoneInput value={phone} onChange={setPhone} /></div>
      <p>If the stored number is full, enter a different valid number here. The old number stays in phone history.</p>
      <div className="form-group"><label>Reason for replacement phone</label><input value={reason} onChange={e => setReason(e.target.value)} /></div>
      <div className="btn-group">
        <button className="btn btn-secondary" disabled={busy} onClick={() => setSelected(null)}>Back</button>
        <button className="btn btn-primary" disabled={busy} onClick={restore}>{busy ? 'Restoring…' : 'Restore customer'}</button>
      </div>
    </> : <>
      <input aria-label="Search deleted customers" placeholder="Search name, phone or customer ID" value={query} onChange={e => { setQuery(e.target.value); setPage(0); }} />
      {rows.map(c => <div key={c.id} style={{ padding: '12px 0', borderBottom: '1px solid var(--border)' }}>
        <strong>{c.full_name}</strong> · {c.phone}<br /><small>{c.id}</small>{' '}
        <button className="btn btn-secondary btn-sm" onClick={() => { setSelected(c); setPhone(inspectPhone(c.phone).normalized ?? c.phone); setReason(''); setError(null); }}>Review restoration</button>
      </div>)}
      {!rows.length && <p>No deleted customers found.</p>}
      <div className="btn-group" style={{ marginTop: 12 }}>
        <button className="btn btn-secondary" disabled={page === 0} onClick={() => setPage(p => p - 1)}>Previous</button>
        <button className="btn btn-secondary" disabled={(page + 1) * 50 >= Number(rows[0]?.total_count ?? 0)} onClick={() => setPage(p => p + 1)}>Next</button>
      </div>
    </>}
  </Modal>;
}
