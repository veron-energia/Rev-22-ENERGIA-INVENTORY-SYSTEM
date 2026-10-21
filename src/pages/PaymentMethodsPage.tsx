import React, { useEffect, useState, useCallback, useMemo } from 'react';
import { ExcelExportButton } from '../components/ExcelExport';
import { supabase } from '../lib/supabase';
import { useAuth } from '../context/AuthContext';
import { PaymentMethod, isOwnerOrManager } from '../types';
import { Modal, NoAccess } from '../components/ui';
import { Plus, Pencil, Trash2, CreditCard, RefreshCw, Lock } from 'lucide-react';
import { paymentQrKind } from '../lib/invoices/paymentQr.mjs';

/** One use of a method by a website order channel (payment_method_web_uses, 429). */
interface WebUse { payment_method_id: string; channel_key: string; channel_mode: string; used_for: string }

const sameName = (a: string, b: string) => a.trim().toLowerCase() === b.trim().toLowerCase();

const PaymentMethodsPage: React.FC = () => {
  const { profile } = useAuth();
  // Access is checked AFTER the hooks below. Returning early here would call
  // no hooks on the first render and every hook on the next, which React
  // treats as a fatal error and blanks the whole app.
  const hasAccess = isOwnerOrManager(profile?.role);
  // Every method, deleted ones too: a deleted method's name can be restored
  // rather than added again (ADMIN-AUTH-11). The table shows the live ones.
  const [all, setAll] = useState<PaymentMethod[]>([]);
  const [webUses, setWebUses] = useState<WebUse[]>([]);
  const [loading, setLoading] = useState(true);
  const [loadErr, setLoadErr] = useState<string | null>(null);
  const [usesErr, setUsesErr] = useState<string | null>(null);
  const [pageErr, setPageErr] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [modalOpen, setModalOpen] = useState(false);
  const [editId, setEditId] = useState<string | null>(null);
  const [name, setName] = useState('');
  const [active, setActive] = useState(true);
  const [saving, setSaving] = useState(false);
  const [err, setErr] = useState<string | null>(null);

  const load = useCallback(async () => {
    setLoading(true);
    const [{ data, error }, uses] = await Promise.all([
      supabase.from('payment_methods').select('*').order('created_at'),
      supabase.rpc('payment_method_web_uses'),
    ]);
    // ADMIN-AUTH-10/-11: a failed read said "No payment methods yet".
    if (error) { setLoadErr(`Could not load payment methods: ${error.message}`); setAll([]); }
    else { setLoadErr(null); setAll((data as PaymentMethod[]) ?? []); }
    if (uses.error) {
      setWebUses([]);
      setUsesErr(`Could not check which methods the website orders use: ${uses.error.message}`);
    } else {
      setWebUses((uses.data as WebUse[]) ?? []);
      setUsesErr(null);
    }
    setLoading(false);
  }, []);
  useEffect(() => { load(); }, [load]);

  const rows = useMemo(() => all.filter(m => !m.deleted_at), [all]);
  const editing = editId ? all.find(m => m.id === editId) ?? null : null;
  const usesOf = (id: string) => webUses.filter(u => u.payment_method_id === id);
  const usesText = (id: string) => usesOf(id)
    .map(u => `the website channel "${u.channel_key}"${u.channel_mode === 'off' ? ' (switched off)' : ''} for ${u.used_for}`)
    .join('; ');

  // While adding: a deleted method with the typed name can be restored.
  const deletedMatch = !editId && name.trim()
    ? all.find(m => m.deleted_at && sameName(m.name, name)) ?? null
    : null;

  const openAdd = () => { setName(''); setActive(true); setEditId(null); setErr(null); setModalOpen(true); };
  const openEdit = (m: PaymentMethod) => { setName(m.name); setActive(m.is_active); setEditId(m.id); setErr(null); setModalOpen(true); };

  const friendly = (message: string) =>
    /duplicate|unique/i.test(message) ? 'That payment method already exists.' : message;

  /** The questions to ask before a risky save. False when the person said no. */
  const confirmRisks = (): boolean => {
    if (!editing) return true;
    const switchingOff = editing.is_active && !active;
    const renaming = editing.name.trim() !== name.trim();
    if (switchingOff && usesOf(editing.id).length > 0 && !window.confirm(
      `Switch off "${editing.name}"?\n\nIt is used by ${usesText(editing.id)}. `
      + 'Website orders paid this way cannot be turned into invoices while it is off.')) return false;
    if (renaming) {
      const before = paymentQrKind({ name: editing.name, is_wallet_credit: editing.is_wallet_credit });
      const after = paymentQrKind({ name, is_wallet_credit: editing.is_wallet_credit });
      if (before && before.match !== after?.match && !window.confirm(
        `Rename "${editing.name}" to "${name.trim()}"?\n\nThe till finds the ${before.label} QR code by the `
        + `method's name, so after this it will no longer show the ${before.label} QR code for this method.`)) return false;
      if (sameName(editing.name, 'HitPay (online)') && usesOf(editing.id).some(u => /HitPay/.test(u.used_for))
          && !window.confirm(`Rename "${editing.name}"?\n\nWebsite orders paid by HitPay find this method by its name. `
            + 'After this, a channel that does not name its HitPay method cannot invoice them.')) return false;
    }
    return true;
  };

  const handleSave = async () => {
    if (!name.trim()) { setErr('Name is required.'); return; }
    const clash = all.find(m => !m.deleted_at && m.id !== editId && sameName(m.name, name));
    if (clash) { setErr(`That payment method already exists: "${clash.name}".`); return; }
    if (!confirmRisks()) return;
    setSaving(true); setErr(null);
    // A system wallet method keeps its name and stays on (the database
    // refuses a rename or switching it off; the Owner, 10 Oct 2026). Only one
    // found off can be saved, to switch it on.
    const payload: { name?: string; is_active: boolean } = editing?.is_system
      ? { is_active: active } : { name: name.trim(), is_active: active };
    const res = editId
      ? await supabase.from('payment_methods').update(payload).eq('id', editId).select('id')
      : await supabase.from('payment_methods').insert(payload).select('id');
    setSaving(false);
    if (res.error) { setErr(friendly(res.error.message)); return; }
    if (!res.data || res.data.length === 0) { setErr('Nothing was saved: your role may not change payment methods.'); return; }
    setModalOpen(false);
    setNotice(editId ? `"${name.trim()}" was saved.` : `"${name.trim()}" was added.`);
    load();
  };

  // ADMIN-AUTH-11: bring a deleted method back (its history stays with it).
  const handleRestore = async (m: PaymentMethod) => {
    setSaving(true); setErr(null);
    const res = await supabase.from('payment_methods')
      .update({ deleted_at: null, is_active: true }).eq('id', m.id).select('id');
    setSaving(false);
    if (res.error) { setErr(friendly(res.error.message)); return; }
    if (!res.data || res.data.length === 0) { setErr('Nothing was restored: your role may not change payment methods.'); return; }
    setModalOpen(false);
    setNotice(`"${m.name}" was restored.`);
    load();
  };

  const handleDelete = async (m: PaymentMethod) => {
    setPageErr(null); setNotice(null);
    const used = usesOf(m.id).length > 0
      ? `\n\nIt is used by ${usesText(m.id)}. Website orders paid this way cannot be turned into invoices once it is deleted.`
      : '';
    if (!window.confirm(`Delete "${m.name}"?${used}`)) return;
    const { data, error } = await supabase.from('payment_methods')
      .update({ deleted_at: new Date().toISOString(), is_active: false }).eq('id', m.id).select('id');
    // ADMIN-AUTH-10: a refused delete used to look as if it had worked.
    if (error) { setPageErr(`"${m.name}" was not deleted: ${error.message}`); return; }
    if (!data || data.length === 0) { setPageErr(`"${m.name}" was not deleted: your role may not change payment methods.`); return; }
    setNotice(`"${m.name}" was deleted. Add it again with the same name to restore it.`);
    load();
  };

  if (!hasAccess) return <NoAccess message="Only Owners and Managers can manage payment methods." />;

  return (
    <div>
      <div className="page-header">
        <div><h2>Payment Methods</h2><p>Methods available when recording invoice payments. Invoices can split across multiple methods.</p></div>
        <div style={{ display: 'flex', gap: 10 }}>
          <ExcelExportButton
            rows={rows} filename="payment-methods" sheetName="Payment Methods"
            columns={[
              { header: 'Method', value: (m: any) => m.name },
              { header: 'Wallet', value: (m: any) => m.is_wallet_credit ? 'Wallet credit' : 'Normal' },
              { header: 'System', value: (m: any) => m.is_system ? 'System' : '' },
              { header: 'Status', value: (m: any) => m.is_active ? 'Active' : 'Inactive' },
            ]} />
          <button className="btn btn-secondary" onClick={load}><RefreshCw size={15} className={loading ? 'spin' : ''} /> Refresh</button>
          <button className="btn btn-primary" onClick={openAdd}><Plus size={16} /> Add Method</button>
        </div>
      </div>

      {notice && <div className="alert alert-success" role="status"><span>✓</span><div>{notice}</div></div>}
      {pageErr && <div className="alert alert-danger" role="alert"><span>⚠</span><div>{pageErr}</div></div>}
      {usesErr && !loadErr && <div className="alert alert-warning" role="alert"><span>⚠</span><div>{usesErr}</div></div>}

      <div className="card">
        <div className="table-wrap">
          {loadErr ? (
            <div className="empty-state" role="alert">
              <p style={{ fontWeight: 600, color: 'var(--danger)' }}>{loadErr}</p>
              <button className="btn btn-secondary" style={{ marginTop: 10 }} onClick={load}>
                <RefreshCw size={14} aria-hidden="true" /> Retry
              </button>
            </div>
          ) : loading ? <div className="empty-state"><RefreshCw size={24} className="spin" style={{ opacity: 0.4 }} /></div>
          : rows.length === 0 ? (
            <div className="empty-state"><CreditCard size={34} style={{ opacity: 0.3, marginBottom: 10 }} /><p style={{ fontWeight: 600 }}>No payment methods yet</p></div>
          ) : (
            <table>
              <thead><tr><th>Method</th><th>Status</th><th></th></tr></thead>
              <tbody>
                {rows.map(m => (
                  <tr key={m.id}>
                    <td>
                      <strong>{m.name}</strong>
                      {m.is_system && (
                        <span className="badge badge-primary" style={{ marginLeft: 8 }}
                              title="One of the Wallet credit types. It is always on, and cannot be renamed, switched off or deleted.">
                          <Lock size={10} aria-hidden="true" /> System
                        </span>
                      )}
                      {usesOf(m.id).length > 0 && (
                        <div style={{ fontSize: 11.5, color: 'var(--text-muted)', marginTop: 2 }}>
                          Used by website orders ({Array.from(new Set(usesOf(m.id).map(u => u.channel_key))).join(', ')})
                        </div>
                      )}
                    </td>
                    <td>{m.is_active ? <span className="badge badge-success">Active</span> : <span className="badge badge-muted">Inactive</span>}</td>
                    <td><div style={{ display: 'flex', gap: 4 }}>
                      {/* A Wallet credit type that is on has nothing to change: it keeps
                          its name and stays on. One found off can be switched on. */}
                      {!(m.is_system && m.is_active) && (
                        <button className="btn btn-secondary btn-sm btn-icon" aria-label={`Edit ${m.name}`} onClick={() => openEdit(m)}><Pencil size={13} /></button>
                      )}
                      {!m.is_system && (
                        <button className="btn btn-danger btn-sm btn-icon" aria-label={`Delete ${m.name}`} onClick={() => void handleDelete(m)}><Trash2 size={13} /></button>
                      )}
                    </div></td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>
      </div>

      {modalOpen && (
        <Modal title={editId ? 'Edit Payment Method' : 'Add Payment Method'} maxWidth={420} confirmClose onClose={() => setModalOpen(false)}
          footer={<><button className="btn btn-secondary" onClick={() => setModalOpen(false)}>Cancel</button>
            <button className="btn btn-primary" onClick={handleSave} disabled={saving}>
              {saving ? 'Saving…' : deletedMatch ? 'Add a new one' : 'Save'}
            </button></>}>
          <div className="form-grid">
            {err && <div className="alert alert-danger" role="alert" style={{ marginBottom: 0 }}><span>⚠</span><div>{err}</div></div>}
            <div className="form-group">
              <label htmlFor="pm-name">Name *</label>
              <input id="pm-name" value={name} onChange={e => setName(e.target.value)} placeholder="e.g. PayNow" autoFocus
                     disabled={!!editing?.is_system} aria-describedby={editing?.is_system ? 'pm-name-hint' : undefined} />
              {editing?.is_system && (
                <span id="pm-name-hint" style={{ fontSize: 11.5, color: 'var(--text-muted)', marginTop: 4, display: 'block' }}>
                  This is one of the Wallet credit types. Its name stays as it is, and once on it stays on.
                </span>
              )}
            </div>
            {deletedMatch && (
              <div className="alert alert-info" role="status" style={{ marginBottom: 0 }}>
                <span>ℹ️</span>
                <div>
                  A deleted method is called "{deletedMatch.name}". Restore it to bring it back with its history,
                  or add a new one with this name.
                  <div style={{ marginTop: 8 }}>
                    <button className="btn btn-primary btn-sm" disabled={saving} onClick={() => void handleRestore(deletedMatch)}>
                      Restore "{deletedMatch.name}"
                    </button>
                  </div>
                </div>
              </div>
            )}
            {/* The Wallet credit types are never switched off (the Owner,
                10 Oct 2026): Active is offered only to switch on one found off. */}
            {!(editing?.is_system && editing.is_active) && (
              <label style={{ display: 'flex', alignItems: 'center', gap: 8, cursor: 'pointer' }}>
                <input type="checkbox" checked={active} onChange={e => setActive(e.target.checked)} style={{ width: 'auto' }} /><span style={{ fontSize: 13 }}>Active</span>
              </label>
            )}
            {editing?.is_system && !editing.is_active && (
              <span role="note" style={{ fontSize: 11.5, color: 'var(--text-muted)', marginTop: -6, display: 'block' }}>
                Customers cannot spend this kind of credit at the till while it is off. Once switched on, it stays on.
              </span>
            )}
            {editing && !editing.is_system && editing.is_active && !active && usesOf(editing.id).length > 0 && (
              <span role="note" style={{ fontSize: 11.5, color: 'var(--text-muted)', marginTop: -6, display: 'block' }}>
                {`Used by ${usesText(editing.id)}. Website orders paid this way cannot be invoiced while it is off.`}
              </span>
            )}
          </div>
        </Modal>
      )}
    </div>
  );
};

export default PaymentMethodsPage;
