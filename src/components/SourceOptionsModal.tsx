import React, { useEffect, useState, useCallback } from 'react';
import { supabase } from '../lib/supabase';
import { Modal } from './ui';
import { Plus, ArrowUp, ArrowDown } from 'lucide-react';

interface Opt { id: string; label: string; sort_order: number; requires_details: boolean; is_active: boolean; }

// Phase 14 — Owner/Manager management of customer-source options.
// Options can be added, edited, reordered and (de)activated; a used option
// can only be deactivated — the server refuses hard deletes.
const SourceOptionsModal: React.FC<{ onClose: () => void }> = ({ onClose }) => {
  const [opts, setOpts] = useState<Opt[]>([]);
  const [err, setErr] = useState<string | null>(null);
  const [newLabel, setNewLabel] = useState('');
  const [newNeedsDetails, setNewNeedsDetails] = useState(false);
  const [busy, setBusy] = useState(false);

  const load = useCallback(async () => {
    const { data } = await supabase.from('customer_source_options')
      .select('*').order('sort_order').order('label');
    setOpts((data as Opt[]) ?? []);
  }, []);
  useEffect(() => { load(); }, [load]);

  const add = async () => {
    if (!newLabel.trim()) return;
    setBusy(true); setErr(null);
    const maxOrder = opts.reduce((m, o) => Math.max(m, o.sort_order), 0);
    const { error } = await supabase.rpc('upsert_customer_source_option', {
      p_label: newLabel.trim(), p_sort_order: maxOrder + 10,
      p_requires_details: newNeedsDetails, p_is_active: true, p_id: null,
    });
    setBusy(false);
    if (error) { setErr(error.message); return; }
    setNewLabel(''); setNewNeedsDetails(false); load();
  };

  const rename = async (o: Opt) => {
    const label = prompt('Rename source option:', o.label);
    if (!label || !label.trim() || label.trim() === o.label) return;
    const { error } = await supabase.rpc('upsert_customer_source_option', {
      p_label: label.trim(), p_sort_order: null, p_requires_details: null, p_is_active: null, p_id: o.id,
    });
    if (error) setErr(error.message); else load();
  };

  const toggleActive = async (o: Opt) => {
    const { error } = await supabase.rpc('set_customer_source_option_active', { p_id: o.id, p_active: !o.is_active });
    if (error) setErr(error.message); else load();
  };

  const move = async (i: number, dir: -1 | 1) => {
    const j = i + dir;
    if (j < 0 || j >= opts.length) return;
    const ids = opts.map(o => o.id);
    [ids[i], ids[j]] = [ids[j], ids[i]];
    const { error } = await supabase.rpc('reorder_customer_source_options', { p_ids: ids });
    if (error) setErr(error.message); else load();
  };

  return (
    <Modal title="Customer Source Options" maxWidth={520} onClose={onClose}
      footer={<button className="btn btn-secondary" onClick={onClose}>Close</button>}>
      <div className="form-grid">
        {err && <div className="alert alert-danger" style={{ fontSize: 12.5 }}>{err}</div>}
        <div style={{ fontSize: 12, color: 'var(--text-muted)' }}>
          These options appear on the public health survey ("How did you hear about us?").
          Options already in use can be deactivated but never deleted.
        </div>
        <div>
          {opts.map((o, i) => (
            <div key={o.id} style={{ display: 'flex', alignItems: 'center', gap: 8, padding: '7px 4px', borderBottom: '1px solid var(--border)' }}>
              <div style={{ display: 'flex', flexDirection: 'column', gap: 2 }}>
                <button className="btn btn-secondary btn-sm btn-icon" style={{ width: 22, height: 18, padding: 0 }} onClick={() => move(i, -1)} disabled={i === 0}><ArrowUp size={11} /></button>
                <button className="btn btn-secondary btn-sm btn-icon" style={{ width: 22, height: 18, padding: 0 }} onClick={() => move(i, 1)} disabled={i === opts.length - 1}><ArrowDown size={11} /></button>
              </div>
              <span style={{ flex: 1, fontSize: 13, fontWeight: 600, opacity: o.is_active ? 1 : 0.5 }}>
                {o.label}
                {o.requires_details && <span style={{ fontWeight: 400, fontSize: 11, color: 'var(--text-muted)' }}> · asks for details</span>}
              </span>
              {!o.is_active && <span className="badge badge-danger">Inactive</span>}
              <button className="btn btn-secondary btn-sm" onClick={() => rename(o)}>Rename</button>
              <button className={`btn btn-sm ${o.is_active ? 'btn-danger' : 'btn-primary'}`} onClick={() => toggleActive(o)}>
                {o.is_active ? 'Deactivate' : 'Activate'}
              </button>
            </div>
          ))}
        </div>
        <div style={{ display: 'flex', gap: 8, alignItems: 'center' }}>
          <input placeholder="New option label" value={newLabel} onChange={e => setNewLabel(e.target.value)} style={{ flex: 1 }} />
          <label style={{ display: 'flex', alignItems: 'center', gap: 5, fontSize: 12 }}>
            <input type="checkbox" checked={newNeedsDetails} onChange={e => setNewNeedsDetails(e.target.checked)} style={{ width: 'auto' }} />
            asks details
          </label>
          <button className="btn btn-primary btn-sm" onClick={add} disabled={busy || !newLabel.trim()}><Plus size={13} /> Add</button>
        </div>
      </div>
    </Modal>
  );
};

export default SourceOptionsModal;
