import React, { useEffect, useState, useCallback, useRef } from 'react';
import { ExcelExportButton } from '../components/ExcelExport';
import { supabase } from '../lib/supabase';
import { useAuth } from '../context/AuthContext';
import { Store as StoreT, Profile, UserStoreAssignment, ROLE_LABELS } from '../types';
import { Modal } from '../components/ui';
import { uploadStoreAsset } from '../lib/storeAssets';
import { Plus, Pencil, Trash2, Store, RefreshCw, Users2, RotateCcw } from 'lucide-react';
import { canManagePlaces, storeAssignmentBlock, worksAtEveryStore } from '../lib/permissions/products';

const StoresPage: React.FC = () => {
  const { profile, assignments: myAssignments } = useAuth();
  const canManage = canManagePlaces(profile?.role);
  // Owners, Admins and Managers see every store (Managers edit any store, as
  // before). Staff and Inventory Managers see the stores they work at. Every
  // store's name stays readable elsewhere: transfers and invoices name them.
  const seesAll = worksAtEveryStore(profile?.role) || profile?.role === 'manager';
  const myStoreIds = myAssignments.map(a => a.store_id);

  const [rows, setRows] = useState<StoreT[]>([]);
  const [loading, setLoading] = useState(true);
  const [modalOpen, setModalOpen] = useState(false);
  const [editId, setEditId] = useState<string | null>(null);
  const [form, setForm] = useState({ name: '', code: '', address: '', phone: '', whatsapp_phone: '', policy_text: '', is_active: true, email: '', website: '', co_reg_no: '', paynow_uen: '', bank_account: '', gst_enabled: false, gst_rate: 9, company_logo_url: '', store_logo_url: '', qr_paynow_url: '', qr_grabpay_url: '', qr_atome_url: '' });
  const [saving, setSaving] = useState(false);
  const [uploadingField, setUploadingField] = useState<string | null>(null);
  const [err, setErr] = useState<string | null>(null);
  // The form is long and the message sits at its top, far above Save. Bring
  // it into view when it appears (a refused switch-off, a code in use, an
  // upload that failed).
  const errRef = useRef<HTMLDivElement | null>(null);
  useEffect(() => { if (err) errRef.current?.scrollIntoView?.({ block: 'nearest' }); }, [err]);

  // Assignment management
  const [assignStore, setAssignStore] = useState<StoreT | null>(null);
  const [allUsers, setAllUsers] = useState<Profile[]>([]);
  const [storeAssignments, setStoreAssignments] = useState<UserStoreAssignment[]>([]);
  const [assignBusy, setAssignBusy] = useState<string | null>(null);
  const [assignErr, setAssignErr] = useState<string | null>(null);

  // A deleted store is hidden, not removed: "Show deleted" lists it with Restore.
  const [showDeleted, setShowDeleted] = useState(false);
  const [pageErr, setPageErr] = useState<string | null>(null);
  const [flash, setFlash] = useState<string | null>(null);
  const [busyId, setBusyId] = useState<string | null>(null);

  const load = useCallback(async () => {
    setLoading(true);
    // Every staff member may read every store's row, so the page itself keeps
    // Staff and Inventory Managers to the stores they work at.
    const q = supabase.from('stores').select('*');
    const { data, error } = await (showDeleted ? q.not('deleted_at', 'is', null) : q.is('deleted_at', null)).order('created_at');
    setPageErr(error ? `Couldn't read the stores: ${error.message}. Refresh to try again.` : null);
    const all = (data as StoreT[]) ?? [];
    setRows(seesAll ? all : all.filter(s => myStoreIds.includes(s.id)));
    setLoading(false);
  }, [showDeleted, seesAll, myStoreIds.join(',')]);
  useEffect(() => { load(); }, [load]);

  const openAdd = () => { setForm({ name: '', code: '', address: '', phone: '', whatsapp_phone: '', policy_text: '', is_active: true, email: '', website: '', co_reg_no: '', paynow_uen: '', bank_account: '', gst_enabled: false, gst_rate: 9, company_logo_url: '', store_logo_url: '', qr_paynow_url: '', qr_grabpay_url: '', qr_atome_url: '' }); setEditId(null); setErr(null); setModalOpen(true); };
  const openEdit = (s: StoreT) => { setForm({
      name: s.name, code: s.code, address: s.address ?? '', phone: s.phone ?? '', whatsapp_phone: (s as any).whatsapp_phone ?? '', policy_text: (s as any).policy_text ?? '', is_active: s.is_active,
      email: s.email ?? '', website: s.website ?? '', co_reg_no: s.co_reg_no ?? '',
      paynow_uen: s.paynow_uen ?? '', bank_account: s.bank_account ?? '',
      gst_enabled: s.gst_enabled ?? false, gst_rate: Number(s.gst_rate ?? 9),
      company_logo_url: s.company_logo_url ?? '', store_logo_url: s.store_logo_url ?? '',
      qr_paynow_url: s.qr_paynow_url ?? '', qr_grabpay_url: s.qr_grabpay_url ?? '', qr_atome_url: s.qr_atome_url ?? '',
    }); setEditId(s.id); setErr(null); setModalOpen(true); };

  const handleSave = async () => {
    if (!form.name.trim() || !form.code.trim()) { setErr('Name and code are required.'); return; }
    if (!form.address.trim()) { setErr('Address is required (used on printed invoices).'); return; }
    if (!form.phone.trim()) { setErr('Phone number is required (used on printed invoices).'); return; }
    setSaving(true); setErr(null);
    const payload = {
      name: form.name.trim(), code: form.code.trim(), address: form.address.trim() || null, phone: form.phone.trim() || null, whatsapp_phone: form.whatsapp_phone.trim() || null, policy_text: form.policy_text.trim() || null, is_active: form.is_active,
      email: form.email.trim() || null, website: form.website.trim() || null, co_reg_no: form.co_reg_no.trim() || null,
      paynow_uen: form.paynow_uen.trim() || null, bank_account: form.bank_account.trim() || null,
      gst_enabled: form.gst_enabled, gst_rate: form.gst_rate || 0,
      company_logo_url: form.company_logo_url || null, store_logo_url: form.store_logo_url || null,
      qr_paynow_url: form.qr_paynow_url || null, qr_grabpay_url: form.qr_grabpay_url || null, qr_atome_url: form.qr_atome_url || null,
    };
    const res = editId
      ? await supabase.from('stores').update(payload).eq('id', editId)
      : await supabase.from('stores').insert(payload);
    // A store or warehouse that still holds stock cannot be switched off: the
    // database says what is left there (the Owner, 9 Oct 2026).
    if (res.error) { setErr(res.error.code === '23505' ? 'That code already exists.' : res.error.message); setSaving(false); return; }
    setSaving(false); setModalOpen(false); load();
  };

  // Delete hides the store. The database refuses while it still holds stock
  // or has stock on the way, and says what (the Owner, 9 Oct 2026).
  const handleDelete = async (s: StoreT) => {
    if (!confirm(`Delete "${s.name}"? It will be hidden. You can bring it back with "Show deleted".`)) return;
    setBusyId(s.id); setPageErr(null); setFlash(null);
    const { error } = await supabase.rpc('soft_delete_store', { p_store_id: s.id });
    setBusyId(null);
    if (error) { setPageErr(error.message); return; }
    setFlash(`${s.name} was deleted.`);
    load();
  };

  const handleRestore = async (s: StoreT) => {
    setBusyId(s.id); setPageErr(null); setFlash(null);
    const { error } = await supabase.rpc('restore_store', { p_store_id: s.id });
    setBusyId(null);
    if (error) { setPageErr(error.message); return; }
    setFlash(`${s.name} is back and active.`);
    load();
  };

  // ── Assignments ──
  const loadAssignments = async (storeId: string) => {
    const { data, error } = await supabase.from('user_store_assignments').select('*').eq('store_id', storeId);
    if (error) setAssignErr(`Couldn't read who works here: ${error.message}`);
    setStoreAssignments((data as UserStoreAssignment[]) ?? []);
  };
  const openAssignments = async (s: StoreT) => {
    setAssignStore(s); setAssignErr(null);
    const { data: users } = await supabase.from('profiles').select('*').is('deleted_at', null).order('full_name');
    setAllUsers((users as Profile[]) ?? []);
    await loadAssignments(s.id);
  };

  // Through the server (assign_user_store, 420): Managers put Staff and
  // Inventory Managers on the stores they work at; only an Owner changes a
  // Manager's stores; nobody changes their own. A refusal is shown.
  const toggleAssignment = async (u: Profile) => {
    if (!assignStore) return;
    const assigned = storeAssignments.some(a => a.user_id === u.id);
    setAssignBusy(u.id); setAssignErr(null);
    const { error } = await supabase.rpc('assign_user_store', {
      p_user_id: u.id, p_store_id: assignStore.id, p_assigned: !assigned,
    });
    setAssignBusy(null);
    if (error) setAssignErr(`${u.full_name}: ${error.message}`);
    await loadAssignments(assignStore.id);
  };

  return (
    <div>
      <div className="page-header">
        <div>
          <h2>Stores</h2>
          <p>{seesAll ? 'All store locations. Choose who works at each store.' : 'The stores you work at.'}</p>
        </div>
        <div style={{ display: 'flex', gap: 10 }}>
          <ExcelExportButton
            rows={rows} filename="stores" sheetName="Stores"
            columns={[
              { header: 'Store', value: (s2: any) => s2.name },
              { header: 'Code', value: (s2: any) => s2.code ?? '' },
              { header: 'Address', value: (s2: any) => s2.address ?? '' },
              { header: 'Phone', value: (s2: any) => s2.phone ?? '' },
              { header: 'WhatsApp', value: (s2: any) => s2.whatsapp_phone ?? '' },
              { header: 'Status', value: (s2: any) => s2.is_active ? 'Active' : 'Inactive' },
            ]} />
          <button className="btn btn-secondary" onClick={load}><RefreshCw size={15} className={loading ? 'spin' : ''} /> Refresh</button>
          {canManage && <button className="btn btn-primary" onClick={openAdd}><Plus size={16} /> Add Store</button>}
        </div>
      </div>

      {canManage && (
        <label style={{ display: 'inline-flex', alignItems: 'center', gap: 6, fontSize: 13, cursor: 'pointer', marginBottom: 12 }}>
          <input type="checkbox" checked={showDeleted} onChange={e => { setShowDeleted(e.target.checked); setFlash(null); }} style={{ width: 'auto' }} />
          Show deleted
        </label>
      )}
      {pageErr && <div className="alert alert-danger" role="alert"><span>⚠</span><div>{pageErr}</div></div>}
      {flash && <div className="alert alert-info" role="status"><span>✓</span><div>{flash}</div></div>}
      {!seesAll && rows.length > 0 && (
        <div className="alert alert-info"><span>ℹ️</span><div>You're viewing the {rows.length} store{rows.length > 1 ? 's' : ''} you work at.</div></div>
      )}

      <div className="card">
        <div className="table-wrap">
          {loading ? <div className="empty-state"><RefreshCw size={24} className="spin" style={{ opacity: 0.4 }} /></div>
          : rows.length === 0 ? (
            <div className="empty-state"><Store size={34} style={{ opacity: 0.3, marginBottom: 10 }} /><p style={{ fontWeight: 600 }}>{showDeleted ? 'No deleted stores' : `No stores ${seesAll ? 'yet' : 'assigned to you'}`}</p></div>
          ) : (
            <table>
              <thead><tr><th>Store</th><th>Code</th><th>Address</th><th>Phone</th><th>Status</th>{canManage && <th></th>}</tr></thead>
              <tbody>
                {rows.map(s => (
                  <tr key={s.id}>
                    <td><strong>{s.name}</strong></td>
                    <td style={{ fontFamily: 'var(--font-display)', fontSize: 12.5 }}>{s.code}</td>
                    <td style={{ color: 'var(--text-secondary)', maxWidth: 240 }}>{s.address || '—'}</td>
                    <td style={{ color: 'var(--text-secondary)', fontSize: 12.5 }}>{s.phone || '—'}</td>
                    <td>{s.deleted_at ? <span className="badge badge-danger">Deleted</span>
                      : s.is_active ? <span className="badge badge-success">Active</span> : <span className="badge badge-muted">Inactive</span>}</td>
                    {canManage && <td>{s.deleted_at
                      ? <button className="btn btn-secondary btn-sm" disabled={busyId === s.id} onClick={() => handleRestore(s)}><RotateCcw size={13} /> Restore</button>
                      : <div style={{ display: 'flex', gap: 4 }}>
                      <button className="btn btn-secondary btn-sm" onClick={() => openAssignments(s)}><Users2 size={13} /> Staff</button>
                      <button className="btn btn-secondary btn-sm btn-icon" title="Edit" onClick={() => openEdit(s)}><Pencil size={13} /></button>
                      <button className="btn btn-danger btn-sm btn-icon" title="Delete" disabled={busyId === s.id} onClick={() => handleDelete(s)}><Trash2 size={13} /></button>
                    </div>}</td>}
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>
      </div>

      {/* Add / Edit modal */}
      {modalOpen && (
        <Modal title={editId ? 'Edit Store' : 'Add Store'} onClose={() => setModalOpen(false)}
          footer={<><button className="btn btn-secondary" onClick={() => setModalOpen(false)}>Cancel</button><button className="btn btn-primary" onClick={handleSave} disabled={saving}>{saving ? 'Saving…' : 'Save'}</button></>}>
          <div className="form-grid">
            {err && <div ref={errRef} className="alert alert-danger" role="alert" style={{ marginBottom: 0 }}><span>⚠</span><div>{err}</div></div>}
            <div className="form-grid-2">
              <div className="form-group"><label>Name *</label><input value={form.name} onChange={e => setForm(f => ({ ...f, name: e.target.value }))} placeholder="Energia Rev22 (Adelphi)" autoFocus /></div>
              <div className="form-group"><label>Code *</label><input value={form.code} onChange={e => setForm(f => ({ ...f, code: e.target.value }))} placeholder="STORE-ADELPHI" /></div>
            </div>
            <div className="form-grid-2">
              <div className="form-group"><label>Address *</label><input value={form.address} onChange={e => setForm(f => ({ ...f, address: e.target.value }))} placeholder="Used on printed invoices" /></div>
              <div className="form-group"><label>Phone *</label><input value={form.phone} onChange={e => setForm(f => ({ ...f, phone: e.target.value }))} placeholder="e.g. 6337 2768" /></div>
              <div className="form-group"><label>WhatsApp Phone</label>
                <input value={form.whatsapp_phone} onChange={e => setForm(f => ({ ...f, whatsapp_phone: e.target.value }))} placeholder="e.g. 9123 4567" />
                <div style={{ fontSize: 11, color: 'var(--text-muted)', marginTop: 3 }}>
                  Printed on invoices as "Shop WhatsApp", in addition to the phone above.
                </div>
              </div>
            </div>

            <div className="form-group">
              <label>Cancellation / Exchange / Refund policy</label>
              <textarea rows={4} value={form.policy_text}
                onChange={e => setForm(f => ({ ...f, policy_text: e.target.value }))}
                placeholder="Printed at the foot of every invoice. Leave blank to print nothing." />
              <div style={{ fontSize: 11, color: 'var(--text-muted)', marginTop: 3 }}>
                Your own wording — this is a business and legal statement, so nothing is assumed on your behalf.
              </div>
            </div>

            <div style={{ fontSize: 12, fontWeight: 700, color: 'var(--text-muted)', textTransform: 'uppercase', letterSpacing: '0.04em', marginTop: 4 }}>Invoice details (per store)</div>
            <div className="form-grid-2">
              <div className="form-group"><label>Email</label><input value={form.email} onChange={e => setForm(f => ({ ...f, email: e.target.value }))} placeholder="info@rev22.com" /></div>
              <div className="form-group"><label>Website</label><input value={form.website} onChange={e => setForm(f => ({ ...f, website: e.target.value }))} placeholder="www.energia.sg" /></div>
            </div>
            <div className="form-grid-2">
              <div className="form-group"><label>Co. Reg No.</label><input value={form.co_reg_no} onChange={e => setForm(f => ({ ...f, co_reg_no: e.target.value }))} placeholder="201104431Z" /></div>
              <div className="form-group"><label>CIMB UEN</label><input value={form.paynow_uen} onChange={e => setForm(f => ({ ...f, paynow_uen: e.target.value }))} placeholder="201104431Z" /></div>
            </div>
            <div className="form-group"><label>CIMB corporate account</label><input value={form.bank_account} onChange={e => setForm(f => ({ ...f, bank_account: e.target.value }))} placeholder="Rev 22 Pte Ltd UOB 348 309 0275" /></div>

            <div className="form-grid-2">
              <label style={{ display: 'flex', alignItems: 'center', gap: 8, cursor: 'pointer' }}>
                <input type="checkbox" checked={form.gst_enabled} onChange={e => setForm(f => ({ ...f, gst_enabled: e.target.checked }))} style={{ width: 'auto' }} /><span style={{ fontSize: 13 }}>Charge GST on invoices</span>
              </label>
              {form.gst_enabled && <div className="form-group" style={{ marginBottom: 0 }}><label>GST Rate (%)</label><input type="number" min={0} step={0.1} value={form.gst_rate || ''} onChange={e => setForm(f => ({ ...f, gst_rate: +e.target.value }))} /></div>}
            </div>

            <div style={{ fontSize: 12, fontWeight: 700, color: 'var(--text-muted)', textTransform: 'uppercase', letterSpacing: '0.04em', marginTop: 4 }}>Logos &amp; QR images (per store)</div>
            {!editId ? (
              <div className="alert alert-info" style={{ marginBottom: 0 }}><span>ℹ️</span><div>Save the store first, then reopen Edit to upload the company logo, store logo, and PayNow / GrabPay / Atome QR images.</div></div>
            ) : (
              <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(150px, 1fr))', gap: 12 }}>
                {([
                  ['company_logo_url', 'Company Logo'],
                  ['store_logo_url', 'Store Logo'],
                  ['qr_paynow_url', 'PayNow QR'],
                  ['qr_grabpay_url', 'GrabPay QR'],
                  ['qr_atome_url', 'Atome QR'],
                ] as [keyof typeof form, string][]).map(([field, label]) => (
                  <div key={field} style={{ border: '1px solid var(--border)', borderRadius: 'var(--radius-sm)', padding: 10, textAlign: 'center' }}>
                    <div style={{ fontSize: 11.5, fontWeight: 600, marginBottom: 6 }}>{label}</div>
                    {form[field] ? <img src={form[field] as string} alt={label} style={{ maxWidth: '100%', maxHeight: 72, objectFit: 'contain', marginBottom: 6 }} />
                      : <div style={{ height: 72, display: 'flex', alignItems: 'center', justifyContent: 'center', color: 'var(--text-muted)', fontSize: 11 }}>None</div>}
                    <label className="btn btn-secondary btn-sm" style={{ cursor: 'pointer', display: 'inline-block' }}>
                      {uploadingField === field ? 'Uploading…' : (form[field] ? 'Replace' : 'Upload')}
                      <input type="file" accept="image/*" style={{ display: 'none' }} disabled={!!uploadingField}
                        onChange={async e => {
                          const file = e.target.files?.[0]; if (!file || !editId) return;
                          setUploadingField(field);
                          try { const url = await uploadStoreAsset(editId, field, file); setForm(f => ({ ...f, [field]: url })); }
                          catch (er: any) { setErr(er.message ?? 'Upload failed'); }
                          finally { setUploadingField(null); e.target.value = ''; }
                        }} />
                    </label>
                    {form[field] && <button type="button" className="btn btn-danger btn-sm" style={{ marginLeft: 4 }} onClick={() => setForm(f => ({ ...f, [field]: '' }))}>Remove</button>}
                  </div>
                ))}
              </div>
            )}

            <label style={{ display: 'flex', alignItems: 'center', gap: 8, cursor: 'pointer' }}>
              <input type="checkbox" checked={form.is_active} onChange={e => setForm(f => ({ ...f, is_active: e.target.checked }))} style={{ width: 'auto' }} /><span style={{ fontSize: 13 }}>Active</span>
            </label>
            {editId && !form.is_active && (
              <p style={{ fontSize: 12.5, color: 'var(--text-muted)', margin: 0 }}>
                A store that still holds stock, or has stock on the way, cannot be switched off. Move or correct that stock first.
              </p>)}
          </div>
        </Modal>
      )}

      {/* Assignments modal */}
      {assignStore && (
        <Modal title={`Staff — ${assignStore.name}`} maxWidth={460} onClose={() => setAssignStore(null)}
          footer={<button className="btn btn-primary" onClick={() => setAssignStore(null)}>Done</button>}>
          <p style={{ fontSize: 13, color: 'var(--text-secondary)', marginBottom: 14 }}>
            Tick who works at this store. Owners and Admins work at every store. Managers put Staff and
            Inventory Managers on the stores they work at; only an Owner changes a Manager's stores.
          </p>
          {assignErr && <div className="alert alert-danger" role="alert" style={{ marginBottom: 10 }}><span>⚠</span><div>{assignErr}</div></div>}
          <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
            {allUsers.filter(u => !worksAtEveryStore(u.role)).map(u => {
              const assigned = storeAssignments.some(a => a.user_id === u.id);
              const block = profile ? storeAssignmentBlock(profile, u, assignStore.id, myStoreIds) : 'Sign in again.';
              return (
                <label key={u.id} title={block ?? undefined} style={{ display: 'flex', alignItems: 'center', gap: 10, padding: '9px 12px', border: '1px solid var(--border)', borderRadius: 'var(--radius-sm)', cursor: block ? 'not-allowed' : 'pointer', opacity: block ? 0.7 : 1, background: assigned ? 'var(--primary-light)' : 'var(--surface)' }}>
                  <input type="checkbox" checked={assigned} disabled={!!block || assignBusy === u.id} onChange={() => toggleAssignment(u)} style={{ width: 'auto' }} />
                  <div style={{ flex: 1 }}>
                    <div style={{ fontSize: 13, fontWeight: 600 }}>{u.full_name}</div>
                    <div style={{ fontSize: 11, color: 'var(--text-muted)' }}>{ROLE_LABELS[u.role]}{block ? ` · ${block}` : ''}</div>
                  </div>
                </label>
              );
            })}
            {allUsers.filter(u => !worksAtEveryStore(u.role)).length === 0 && (
              <p style={{ fontSize: 13, color: 'var(--text-muted)', textAlign: 'center', padding: 16 }}>No assignable users yet. Create users in Users &amp; Roles first.</p>
            )}
          </div>
        </Modal>
      )}
    </div>
  );
};

export default StoresPage;
