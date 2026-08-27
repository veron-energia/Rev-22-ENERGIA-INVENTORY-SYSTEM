import React, { useEffect, useState, useCallback, useMemo } from 'react';
import { ExcelExportButton } from '../components/ExcelExport';
import { supabase } from '../lib/supabase';
import { useAuth } from '../context/AuthContext';
import { Customer, CustomerGender, isOwnerOrManager } from '../types';
import { Modal } from '../components/ui';
import { Plus, Pencil, Trash2, Search, Users, RefreshCw, Eye, Phone, ChevronDown, ChevronRight } from 'lucide-react';
import { CustomerSearchSelect } from '../components/SearchSelect';

// join_person_name() in the database: the two parts, trimmed, single-spaced,
// with either side allowed to be empty. Mirrored here so the name the form
// shows is the name that gets stored.
export const joinPersonName = (first?: string | null, last?: string | null) =>
  [String(first ?? '').trim(), String(last ?? '').trim()].filter(Boolean).join(' ');

const blank = (c?: Customer) => ({
  // Existing records were split by migration 92 — first word, then the rest —
  // so anyone created before this has both parts already.
  first_name: c?.first_name ?? '', last_name: c?.last_name ?? '',
  phone: c?.phone ?? '', email: c?.email ?? '',
  date_of_birth: c?.date_of_birth ?? '', gender: (c?.gender ?? '') as CustomerGender | '',
  gender_other: c?.gender_other ?? '', occupation: c?.occupation ?? '',
  notes: c?.notes ?? '', is_active: c?.is_active ?? true,
  referred_by: c?.referred_by ?? '',
});

const CustomersPage: React.FC = () => {
  const { profile } = useAuth();
  const canComplete = isOwnerOrManager(profile?.role);   // complete profile view: Owner/Manager only
  const [rows, setRows] = useState<Customer[]>([]);
  const [delFor, setDelFor] = useState<Customer | null>(null);
  const [delName, setDelName] = useState('');
  const [delReason, setDelReason] = useState('');
  const [delBusy, setDelBusy] = useState(false);
  const [delErr, setDelErr] = useState<string | null>(null);
  const PAGE_SIZE = 50;
  const [page, setPage] = useState(0);
  const [totalCount, setTotalCount] = useState(0);
  const [debouncedSearch, setDebouncedSearch] = useState('');
  const [phoneHistory, setPhoneHistory] = useState<{ customer_id: string; phone: string; reason: string | null; created_at: string }[]>([]);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState('');
  // Phase 14 — customer source: filter + staff correction.
  const [sourceFilter, setSourceFilter] = useState('');
  const [sourceOpts, setSourceOpts] = useState<{ id: string; label: string; requires_details: boolean }[]>([]);
  const [srcFor, setSrcFor] = useState<Customer | null>(null);
  const [srcOptId, setSrcOptId] = useState('');
  const [srcDetails, setSrcDetails] = useState('');
  const [srcReason, setSrcReason] = useState('');
  const [srcErr, setSrcErr] = useState<string | null>(null);
  const [srcBusy, setSrcBusy] = useState(false);
  const [modalOpen, setModalOpen] = useState(false);
  const [editId, setEditId] = useState<string | null>(null);
  const [form, setForm] = useState(blank());
  const [saving, setSaving] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [profileFor, setProfileFor] = useState<Customer | null>(null);
  const [overviewFor, setOverviewFor] = useState<Customer | null>(null);
  const [overview, setOverview] = useState<any>(null);
  const [credit, setCredit] = useState<any>(null);
  const [creditRows, setCreditRows] = useState<any[]>([]);
  const [creditForm, setCreditForm] = useState<any>(null);
  const [creditBusy, setCreditBusy] = useState(false);
  const [creditErr, setCreditErr] = useState<string | null>(null);
  const [creditStores, setCreditStores] = useState<{ id: string; name: string }[]>([]);
  const [ovLoading, setOvLoading] = useState(false);
  const [profileStats, setProfileStats] = useState<any>(null);
  const [timeline, setTimeline] = useState<any[] | null>(null);
  const [expandedInv, setExpandedInv] = useState<Record<string, boolean>>({});
  const [phoneFor, setPhoneFor] = useState<Customer | null>(null);
  const [newPhone, setNewPhone] = useState('');
  const [phoneReason, setPhoneReason] = useState('');
  const [phoneErr, setPhoneErr] = useState<string | null>(null);
  const [phoneBusy, setPhoneBusy] = useState(false);
  const submitPhoneChange = async () => {
    if (!phoneFor) return;
    if (!newPhone.trim()) { setPhoneErr('Enter the new phone number.'); return; }
    if (!phoneReason.trim()) { setPhoneErr('A reason is required.'); return; }
    setPhoneBusy(true); setPhoneErr(null);
    const { error } = await supabase.rpc('change_customer_phone', { p_customer_id: phoneFor.id, p_new_phone: newPhone.trim(), p_reason: phoneReason.trim() });
    setPhoneBusy(false);
    if (error) { setPhoneErr(error.message); return; }
    setPhoneFor(null); load();
  };

  const load = useCallback(async () => {
    setLoading(true);
    // Searching and paging happen in the database. The customer table is far
    // too large to hold in the browser, so only one page is ever fetched.
    const [cust, ph, srcs] = await Promise.all([
      supabase.rpc('search_customers', {
        p_query: debouncedSearch.trim() || null,
        p_source: sourceFilter || null,
        p_limit: PAGE_SIZE,
        p_offset: page * PAGE_SIZE,
      }),
      supabase.from('customer_phone_history').select('customer_id,phone,reason,created_at'),
      supabase.rpc('active_customer_source_options'),
    ]);
    const list = (cust.data as any[]) ?? [];
    setRows(list as Customer[]);
    setTotalCount(list.length > 0 ? Number(list[0].total_count) : 0);
    setPhoneHistory((ph.data as any[]) ?? []);
    setSourceOpts((srcs.data as any[]) ?? []);
    setLoading(false);
  }, [debouncedSearch, sourceFilter, page]);

  useEffect(() => { load(); }, [load]);
  useEffect(() => {
    const t = setTimeout(() => { setDebouncedSearch(search); setPage(0); }, 300);
    return () => clearTimeout(t);
  }, [search]);
  useEffect(() => { setPage(0); }, [sourceFilter]);

  const openOverview = async (c: Customer) => {
    setOverviewFor(c); setOverview(null); setOvLoading(true);
    const { data } = await supabase.rpc('customer_overview', { p_customer_id: c.id });
    setOverview(data ?? null); setOvLoading(false);
    void loadCredit(c.id);
  };

  const loadCredit = async (customerId: string) => {
    if (creditStores.length === 0) {
      const { data: st } = await supabase.from('stores').select('id,name').is('deleted_at', null).order('name');
      setCreditStores((st as any[]) ?? []);
    }
    const { data: bal } = await supabase.rpc('customer_credit_balances', { p_customer_id: customerId });
    setCredit(bal ?? null);
    const { data: st } = await supabase.rpc('customer_credit_statement',
      { p_customer_id: customerId, p_from: null, p_to: null });
    setCreditRows((st as any[]) ?? []);
  };

  const submitCredit = async () => {
    if (!creditForm || !overviewFor) return;
    setCreditBusy(true); setCreditErr(null);
    let error: any = null;
    if (creditForm.mode === 'legacy') {
      ({ error } = await supabase.rpc('add_legacy_credit', {
        p_customer_id: overviewFor.id, p_category: creditForm.category,
        p_amount: Number(creditForm.amount), p_original_purchase_date: creditForm.purchase_date || null,
        p_store_id: creditForm.store_id || null, p_reference_no: creditForm.reference_no || null,
        p_note: creditForm.note, p_effective_date: creditForm.effective_date || null,
      }));
    } else {
      ({ error } = await supabase.rpc('adjust_customer_credit', {
        p_customer_id: overviewFor.id, p_category: creditForm.category,
        p_direction: creditForm.direction, p_amount: Number(creditForm.amount),
        p_reason: creditForm.reason, p_reference_no: creditForm.reference_no || null,
        p_effective_date: creditForm.effective_date || null, p_note: creditForm.note || null,
        p_store_id: creditForm.store_id || null,
      }));
    }
    setCreditBusy(false);
    if (error) { setCreditErr(error.message); return; }
    setCreditForm(null); await loadCredit(overviewFor.id);
  };
  const openProfile = async (c: Customer) => {
    setProfileFor(c); setProfileStats(null); setTimeline(null); setExpandedInv({});
    const { data } = await supabase.rpc('customer_profile_stats', { p_customer_id: c.id });
    setProfileStats(data ?? {});
    if (canComplete) {
      const { data: tl } = await supabase.rpc('customer_purchase_timeline', { p_customer_id: c.id });
      setTimeline((tl as any[]) ?? []);
    }
  };

  const openAdd = () => { setForm(blank()); setEditId(null); setErr(null); setModalOpen(true); };
  const openEdit = (c: Customer) => { setForm(blank(c)); setEditId(c.id); setErr(null); setModalOpen(true); };

  const handleSave = async () => {
    // A first name is required, matching update_survey_particulars(), which
    // raises 'A first name is required'. A last name is optional — plenty of
    // customers give only one name.
    if (!form.first_name.trim()) { setErr('First name is required.'); return; }
    if (!form.phone.trim()) { setErr('Phone number is required (must be unique).'); return; }
    setSaving(true); setErr(null);
    const payload = {
      first_name: form.first_name.trim(),
      last_name: form.last_name.trim() || null,
      // Derived, never typed separately, so it cannot drift from the parts.
      full_name: joinPersonName(form.first_name, form.last_name),
      phone: form.phone.trim(),
      email: form.email.trim() || null,
      date_of_birth: form.date_of_birth || null,
      gender: form.gender || null,
      gender_other: form.gender === 'other' ? (form.gender_other.trim() || null) : null,
      occupation: form.occupation.trim() || null,
      notes: form.notes.trim() || null, is_active: form.is_active,
      referred_by: form.referred_by || null, is_referrer: true,
    };
    const res = editId
      ? await supabase.from('customers').update(payload).eq('id', editId)
      : await supabase.from('customers').insert(payload);
    if (res.error) {
      setErr(res.error.message.includes('duplicate') || res.error.message.includes('unique')
        ? 'A customer with this phone number already exists. Phone numbers must be unique.'
        : res.error.message);
      setSaving(false); return;
    }
    setSaving(false); setModalOpen(false); load();
  };

  // Deleting now goes through delete_customer(), which checks the role, matches
  // the typed name, refuses to strand credit or entitlements, and records who
  // did it. Writing to the table directly was blocked by RLS and, worse, threw
  // away the error — the click simply did nothing.
  const handleDelete = (c: Customer) => {
    setDelFor(c);
    setDelName('');
    setDelReason('');
    setDelErr(null);
  };

  const confirmDelete = async () => {
    if (!delFor) return;
    setDelBusy(true); setDelErr(null);
    const { error } = await supabase.rpc('delete_customer', {
      p_customer_id: delFor.id,
      p_confirm_name: delName,
      p_reason: delReason.trim() || null,
    });
    setDelBusy(false);
    if (error) { setDelErr(error.message); return; }
    setDelFor(null);
    load();
  };

  const histByPhone = useMemo(() => {
    const m = new Map<string, string[]>();
    phoneHistory.forEach(h => { const a = m.get(h.customer_id) ?? []; a.push(h.phone); m.set(h.customer_id, a); });
    return m;
  }, [phoneHistory]);

  // The database has already applied the search and the source filter.
  const filtered = rows;

  // The list is server-paginated, so the on-screen rows are only one page.
  // Export re-runs the same search without the page limit.
  const fetchAllForExport = async () => {
    const out: any[] = [];
    const PAGE = 1000;
    for (let offset = 0; ; offset += PAGE) {
      const { data } = await supabase.rpc('search_customers', {
        p_query: debouncedSearch.trim() || null,
        p_source: sourceFilter || null,
        p_limit: PAGE, p_offset: offset,
      });
      const batch = (data as any[]) ?? [];
      out.push(...batch);
      if (batch.length < PAGE) break;
    }
    return out;
  };


  return (
    <div>
      <div className="page-header">
        <div><h2>Customers</h2><p>Customer database. Phone numbers are unique across all stores.</p></div>
        <div style={{ display: 'flex', gap: 10 }}>
          <ExcelExportButton
            rows={filtered} filename="customers" sheetName="Customers"
            dateOf={(c: any) => c.created_at} dateLabel="Created"
            fetchAll={fetchAllForExport}
            columns={[
              { header: 'Name', value: (c: any) => c.full_name },
              { header: 'Phone', value: (c: any) => c.phone ?? '' },
              { header: 'Email', value: (c: any) => c.email ?? '' },
              { header: 'Customer ID', value: (c: any) => (String(c.notes ?? '').match(/CUST-\d+/i) || [''])[0] },
              { header: 'Source', value: (c: any) => c.source_label ?? '' },
              { header: 'Created', value: (c: any) => c.created_at ? new Date(c.created_at).toLocaleDateString('en-GB') : '' },
              { header: 'Status', value: (c: any) => c.is_active ? 'Active' : 'Inactive' },
            ]} />

          {/* Same data and filters as the export above; the difference is that
              you choose which columns go into the sheet. A few extra fields are
              offered here that the standard export does not carry. */}
          <ExcelExportButton
            rows={filtered} filename="customers-selected" sheetName="Customers"
            label="Special Export" selectableColumns
            dateOf={(c: any) => c.created_at} dateLabel="Created"
            fetchAll={fetchAllForExport}
            columns={[
              { header: 'Name', value: (c: any) => c.full_name },
              { header: 'First Name', value: (c: any) => c.first_name ?? '' },
              { header: 'Last Name', value: (c: any) => c.last_name ?? '' },
              { header: 'Phone', value: (c: any) => c.phone ?? '' },
              { header: 'Email', value: (c: any) => c.email ?? '' },
              { header: 'Customer ID', value: (c: any) => (String(c.notes ?? '').match(/CUST-\d+/i) || [''])[0] },
              { header: 'Source', value: (c: any) => c.source_label ?? '' },
              { header: 'Source Details', value: (c: any) => c.source_details ?? '' },
              { header: 'Date of Birth', value: (c: any) => c.date_of_birth ? new Date(c.date_of_birth).toLocaleDateString('en-GB') : '' },
              { header: 'Gender', value: (c: any) => c.gender ?? '' },
              { header: 'Occupation', value: (c: any) => c.occupation ?? '' },
              { header: 'Address', value: (c: any) => c.address ?? '' },
              // The loaded page does not hold every customer, so a name lookup
              // would print blanks for referrers who are not on screen. The id
              // is exported instead: always correct, and joinable in the sheet.
              { header: 'Referred By (ID)', value: (c: any) => c.referred_by ?? '' },
              { header: 'Is Referrer', value: (c: any) => c.is_referrer ? 'Yes' : 'No' },
              { header: 'Notes', value: (c: any) => c.notes ?? '' },
              { header: 'Created', value: (c: any) => c.created_at ? new Date(c.created_at).toLocaleDateString('en-GB') : '' },
              { header: 'Status', value: (c: any) => c.is_active ? 'Active' : 'Inactive' },
            ]} />
          <button className="btn btn-secondary" onClick={load}><RefreshCw size={15} className={loading ? 'spin' : ''} /> Refresh</button>
          <button className="btn btn-primary" onClick={openAdd}><Plus size={16} /> Add Customer</button>
        </div>
      </div>

      <div style={{ marginBottom: 14, display: 'flex', gap: 8, alignItems: 'center', flexWrap: 'wrap' }}>
        <div style={{ position: 'relative', flex: '1 1 320px', maxWidth: 380 }}>
          <Search size={15} style={{ position: 'absolute', left: 11, top: '50%', transform: 'translateY(-50%)', color: 'var(--text-muted)', pointerEvents: 'none' }} />
          <input value={search} onChange={e => setSearch(e.target.value)} placeholder="Search name, customer ID, phone (incl. old), or email…" style={{ paddingLeft: 34, width: '100%' }} />
        </div>
        <select value={sourceFilter} onChange={e => setSourceFilter(e.target.value)} style={{ maxWidth: 190 }} title="Filter by customer source">
          <option value="">All sources</option>
          {sourceOpts.map(o => <option key={o.id} value={o.id}>{o.label}</option>)}
          <option value="__none">No source recorded</option>
        </select>
      </div>

      <div className="card">
        <div className="table-wrap">
          {loading ? <div className="empty-state"><RefreshCw size={24} className="spin" style={{ opacity: 0.4 }} /></div>
          : filtered.length === 0 ? <div className="empty-state"><Users size={32} style={{ opacity: 0.3 }} /><p style={{ fontWeight: 600, marginTop: 8 }}>{debouncedSearch || sourceFilter ? 'No customers match this search' : 'No customers yet'}</p></div>
          : (
            <table>
              <thead><tr><th>Name</th><th>Phone</th><th>Email</th><th>Source</th><th>Status</th><th></th></tr></thead>
              <tbody>
                {filtered.map(c => (
                  <tr key={c.id}>
                    <td><strong>{c.full_name}</strong>{c.notes && <div style={{ fontSize: 11.5, color: 'var(--text-muted)' }}>{c.notes.slice(0, 40)}</div>}</td>
                    <td style={{ fontFamily: 'var(--font-display)', fontSize: 13 }}>{c.phone}</td>
                    <td style={{ color: 'var(--text-secondary)' }}>{c.email || '—'}</td>
                    <td style={{ fontSize: 12.5 }}>
                      {(c as any).source_label ?? <span style={{ color: 'var(--text-muted)' }}>—</span>}
                      {(c as any).source_details && <div style={{ fontSize: 11, color: 'var(--text-muted)' }}>{(c as any).source_details}</div>}
                    </td>
                    <td>{c.is_active ? <span className="badge badge-success">Active</span> : <span className="badge badge-muted">Inactive</span>}</td>
                    <td><div style={{ display: 'flex', gap: 4 }}>
                      <button className="btn btn-secondary btn-sm" onClick={() => openOverview(c)}><Eye size={13} /> View</button>
                      <button className="btn btn-secondary btn-sm" onClick={() => openProfile(c)}>Profile</button>
                      <button className="btn btn-secondary btn-sm btn-icon" title="Change phone" onClick={() => { setPhoneFor(c); setNewPhone(''); setPhoneReason(''); setPhoneErr(null); }}><Phone size={13} /></button>
                      <button className="btn btn-secondary btn-sm" title="Change customer source (old surveys keep their snapshot)"
                        onClick={() => { setSrcFor(c); setSrcOptId((c as any).source_option_id ?? ''); setSrcDetails((c as any).source_details ?? ''); setSrcReason(''); setSrcErr(null); }}>Source</button>
                      <button className="btn btn-secondary btn-sm btn-icon" onClick={() => openEdit(c)}><Pencil size={13} /></button>
                      {/* canComplete is Owner/Manager, matching delete_customer's
                          own check — staff should not be offered a button that
                          the database will refuse. */}
                      {canComplete && <button className="btn btn-danger btn-sm btn-icon"
                        title="Delete customer" onClick={() => handleDelete(c)}><Trash2 size={13} /></button>}
                    </div></td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>
        {!loading && totalCount > 0 && (
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center',
                        padding: '10px 12px', borderTop: '1px solid var(--border)', flexWrap: 'wrap', gap: 8 }}>
            <div style={{ fontSize: 12.5, color: 'var(--text-muted)' }}>
              Showing {page * PAGE_SIZE + 1}–{Math.min((page + 1) * PAGE_SIZE, totalCount)} of {totalCount.toLocaleString()}
              {debouncedSearch ? ' matching' : ''} customer{totalCount === 1 ? '' : 's'}
            </div>
            <div style={{ display: 'flex', gap: 6, alignItems: 'center' }}>
              <button className="btn btn-secondary btn-sm" disabled={page === 0}
                onClick={() => setPage(p => Math.max(0, p - 1))}>Previous</button>
              <span style={{ fontSize: 12.5, color: 'var(--text-muted)' }}>
                Page {page + 1} of {Math.max(1, Math.ceil(totalCount / PAGE_SIZE))}
              </span>
              <button className="btn btn-secondary btn-sm"
                disabled={(page + 1) * PAGE_SIZE >= totalCount}
                onClick={() => setPage(p => p + 1)}>Next</button>
            </div>
          </div>
        )}
      </div>

      {delFor && (() => {
        // Compared the same way the database does: case-insensitive, with runs
        // of whitespace collapsed. The point is to make someone read the name,
        // not to test their typing.
        const norm = (v: string) => v.trim().toLowerCase().replace(/\s+/g, ' ');
        const matches = norm(delName) === norm(delFor.full_name ?? '');
        return (
          <Modal title="Delete customer" maxWidth={460} onClose={() => setDelFor(null)}
            footer={<>
              <button className="btn btn-secondary" onClick={() => setDelFor(null)}>Cancel</button>
              <button className="btn btn-danger" onClick={confirmDelete}
                disabled={delBusy || !matches}>
                {delBusy ? 'Deleting…' : 'Delete customer'}
              </button>
            </>}>
            <div className="form-grid">
              <div style={{ fontSize: 13 }}>
                This removes <strong>{delFor.full_name}</strong> from the customer list.
                Their invoices and history are kept, and an Owner or Manager can restore them.
              </div>

              {delErr && <div className="alert alert-danger" style={{ marginBottom: 0 }}>
                <span>⚠</span><div>{delErr}</div></div>}

              <div className="form-group" style={{ marginBottom: 0 }}>
                <label>Type <strong>{delFor.full_name}</strong> to confirm *</label>
                <input value={delName} autoFocus
                  placeholder={delFor.full_name ?? ''}
                  onChange={e => setDelName(e.target.value)} />
                {delName.length > 0 && !matches && (
                  <div style={{ fontSize: 11.5, color: 'var(--danger)', marginTop: 3 }}>
                    That does not match the customer's name.
                  </div>
                )}
              </div>

              <div className="form-group" style={{ marginBottom: 0 }}>
                <label>Reason</label>
                <input value={delReason} onChange={e => setDelReason(e.target.value)}
                  placeholder="Duplicate record, created in error…" />
                <div style={{ fontSize: 11, color: 'var(--text-muted)', marginTop: 3 }}>
                  Recorded against the deletion, alongside who performed it.
                </div>
              </div>
            </div>
          </Modal>
        );
      })()}

      {modalOpen && (
        <Modal title={editId ? 'Edit Customer' : 'Add Customer'} maxWidth={460} onClose={() => setModalOpen(false)}
          footer={<><button className="btn btn-secondary" onClick={() => setModalOpen(false)}>Cancel</button><button className="btn btn-primary" onClick={handleSave} disabled={saving}>{saving ? 'Saving…' : 'Save'}</button></>}>
          <div className="form-grid">
            {err && <div className="alert alert-danger" style={{ marginBottom: 0 }}><span>⚠</span><div>{err}</div></div>}
            <div className="form-grid-2">
              {/* Two fields, matching the health survey exactly, so a name
                  entered here needs no splitting to sync across. */}
              <div className="form-grid-2">
                <div className="form-group" style={{ marginBottom: 0 }}>
                  <label>First Name *</label>
                  <input value={form.first_name} autoFocus
                    onChange={e => setForm(f => ({ ...f, first_name: e.target.value }))} />
                </div>
                <div className="form-group" style={{ marginBottom: 0 }}>
                  <label>Last Name</label>
                  <input value={form.last_name}
                    placeholder="Optional"
                    onChange={e => setForm(f => ({ ...f, last_name: e.target.value }))} />
                </div>
              </div>
              {/* What will actually be stored and printed, so there is no doubt
                  about how the two parts come together. */}
              {(form.first_name.trim() || form.last_name.trim()) && (
                <div style={{ fontSize: 11.5, color: 'var(--text-muted)', marginTop: -6 }}>
                  Will be shown as <strong>{joinPersonName(form.first_name, form.last_name)}</strong>
                </div>
              )}
              <div className="form-group"><label>Phone * (unique)</label><input value={form.phone} onChange={e => setForm(f => ({ ...f, phone: e.target.value }))} placeholder="e.g. 91234567" /></div>
            </div>
            <div className="form-grid-2">
              <div className="form-group"><label>Email</label><input type="email" value={form.email} onChange={e => setForm(f => ({ ...f, email: e.target.value }))} placeholder="Optional" /></div>
              <div className="form-group"><label>Date of Birth</label><input type="date" value={form.date_of_birth} onChange={e => setForm(f => ({ ...f, date_of_birth: e.target.value }))} /></div>
            </div>
            <div className="form-grid-2">
              <div className="form-group"><label>Gender</label>
                <select value={form.gender} onChange={e => setForm(f => ({ ...f, gender: e.target.value as CustomerGender | '' }))}>
                  <option value="">— Not specified —</option>
                  <option value="male">Male</option>
                  <option value="female">Female</option>
                  <option value="other">Other</option>
                </select>
              </div>
              <div className="form-group"><label>Occupation</label><input value={form.occupation} onChange={e => setForm(f => ({ ...f, occupation: e.target.value }))} placeholder="Optional" /></div>
            </div>
            {form.gender === 'other' && (
              <div className="form-group"><label>Please specify gender</label><input value={form.gender_other} onChange={e => setForm(f => ({ ...f, gender_other: e.target.value }))} placeholder="Free text" autoFocus /></div>
            )}
            <div className="form-group"><label>Notes</label><textarea rows={2} value={form.notes} onChange={e => setForm(f => ({ ...f, notes: e.target.value }))} placeholder="Optional" /></div>
            <div className="form-group">
              <label>Referred by (optional)</label>
              <CustomerSearchSelect
                value={form.referred_by}
                onChange={v => setForm(f => ({ ...f, referred_by: v }))}
                placeholder="Search name, phone or email…"
                excludeId={editId ?? undefined} />
              <span style={{ fontSize: 11.5, color: 'var(--text-muted)', marginTop: 4, display: 'block' }}>The customer who introduced this customer. Drives Tier 1 / Tier 2 commission.</span>
            </div>
            <label style={{ display: 'flex', alignItems: 'center', gap: 8, cursor: 'pointer' }}>
              <input type="checkbox" checked={form.is_active} onChange={e => setForm(f => ({ ...f, is_active: e.target.checked }))} style={{ width: 'auto' }} /><span style={{ fontSize: 13 }}>Active</span>
            </label>
          </div>
        </Modal>
      )}

      {overviewFor && (
        <Modal title={`${overviewFor.full_name}`} maxWidth={640} onClose={() => setOverviewFor(null)}
          footer={<button className="btn btn-secondary" onClick={() => setOverviewFor(null)}>Close</button>}>
          {ovLoading || !overview ? <div style={{ textAlign: 'center', padding: 30, color: 'var(--text-muted)' }}>Loading…</div> : (
            <div style={{ display: 'flex', flexDirection: 'column', gap: 14, fontSize: 13 }}>
              {credit && (
                <section>
                  <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', flexWrap: 'wrap', gap: 6 }}>
                    <div style={{ fontWeight: 700 }}>Credit wallet</div>
                    {isOwnerOrManager(profile?.role) && (
                      <div style={{ display: 'flex', gap: 6 }}>
                        <button className="btn btn-secondary btn-sm" onClick={() => { setCreditErr(null); setCreditForm({ mode: 'legacy', category: 'legacy', amount: '', purchase_date: '', store_id: '', reference_no: '', note: '', effective_date: '' }); }}>Opening balance</button>
                        <button className="btn btn-secondary btn-sm" onClick={() => { setCreditErr(null); setCreditForm({ mode: 'adjust', category: 'paid', direction: 'increase', amount: '', reason: '', reference_no: '', note: '', effective_date: '', store_id: '' }); }}>Adjust</button>
                      </div>
                    )}
                  </div>
                  <div style={{ display: 'flex', gap: 14, flexWrap: 'wrap', marginTop: 6, alignItems: 'baseline' }}>
                    <div>
                      <div style={{ fontSize: 20, fontWeight: 700, fontFamily: 'var(--font-display)' }}>
                        S${Number(credit.available_total ?? 0).toFixed(2)}
                      </div>
                      <div style={{ fontSize: 11, color: 'var(--text-muted)' }}>available, all stores</div>
                    </div>
                    <div style={{ display: 'flex', gap: 10, flexWrap: 'wrap', fontSize: 12 }}>
                      {(['paid','bonus','legacy','promotional','exchange'] as const).map(k => (
                        <div key={k}>
                          <div style={{ color: 'var(--text-muted)', textTransform: 'capitalize' }}>{k}</div>
                          <div style={{ fontWeight: 600 }}>S${Number(credit.categories?.[k] ?? 0).toFixed(2)}</div>
                        </div>
                      ))}
                    </div>
                  </div>
                  {creditRows.length > 0 && (
                    <div style={{ marginTop: 8, maxHeight: 190, overflowY: 'auto', border: '1px solid var(--border)', borderRadius: 'var(--radius-sm)' }}>
                      <table style={{ fontSize: 11.5 }}>
                        <thead><tr><th>Date</th><th>Description</th><th>Category</th><th style={{ textAlign: 'right' }}>Added</th><th style={{ textAlign: 'right' }}>Used</th><th style={{ textAlign: 'right' }}>Reversed</th><th style={{ textAlign: 'right' }}>Balance</th></tr></thead>
                        <tbody>
                          {creditRows.map(r => (
                            <tr key={r.entry_seq}>
                              <td>{r.entry_date ? new Date(r.entry_date).toLocaleDateString('en-GB') : '—'}</td>
                              <td>{r.description}{r.reference_no ? <div style={{ color: 'var(--text-muted)' }}>{r.reference_no}</div> : null}</td>
                              <td style={{ textTransform: 'capitalize' }}>{r.category}</td>
                              <td style={{ textAlign: 'right', color: 'var(--success)' }}>{r.credit_added != null ? Number(r.credit_added).toFixed(2) : ''}</td>
                              <td style={{ textAlign: 'right' }}>{r.credit_used != null ? Number(r.credit_used).toFixed(2) : ''}</td>
                              <td style={{ textAlign: 'right', color: 'var(--danger)' }}>{r.credit_reversed != null ? Number(r.credit_reversed).toFixed(2) : ''}</td>
                              <td style={{ textAlign: 'right', fontWeight: 600 }}>{Number(r.wallet_balance).toFixed(2)}</td>
                            </tr>
                          ))}
                        </tbody>
                      </table>
                    </div>
                  )}
                </section>
              )}
              <section>
                <div style={{ fontWeight: 700, marginBottom: 4 }}>Affiliate</div>
                <div style={{ color: 'var(--text-muted)' }}>{overview.affiliate_state?.eligible ? 'Eligible' : (overview.affiliate_state?.block_reason ?? overview.affiliate_state?.state ?? '—')}</div>
              </section>
              {overview.refunds?.length > 0 && (
                <section>
                  <div style={{ fontWeight: 700, marginBottom: 4 }}>Refunds / cancellations</div>
                  {overview.refunds.map((r: any, i: number) => <div key={i} style={{ color: 'var(--text-muted)', fontSize: 12 }}>{r.invoice} · S${Number(r.amount).toFixed(2)} · {r.kind} · {r.reason}</div>)}
                </section>
              )}
              {overview.purchased_therapy?.length > 0 && (
                <section>
                  <div style={{ fontWeight: 700, marginBottom: 4 }}>Purchased therapy</div>
                  {overview.purchased_therapy.map((t: any, i: number) => <div key={i} style={{ color: 'var(--text-muted)', fontSize: 12 }}>{t.no} · {t.package} · {String(t.status).replace('_', ' ')}{t.expiry ? ` · expires ${new Date(t.expiry).toLocaleDateString('en-GB')}` : ''}</div>)}
                </section>
              )}
              {overview.legacy_therapy?.length > 0 && (
                <section>
                  <div style={{ fontWeight: 700, marginBottom: 4 }}>Legacy therapy</div>
                  {overview.legacy_therapy.map((t: any, i: number) => <div key={i} style={{ color: 'var(--text-muted)', fontSize: 12 }}>{t.no} · {t.package} · {t.status}</div>)}
                </section>
              )}
              {overview.deleted_invoices?.length > 0 && (
                <section>
                  <div style={{ fontWeight: 700, marginBottom: 4 }}>Deleted invoice history</div>
                  {overview.deleted_invoices.map((iv: any, i: number) => <div key={i} style={{ color: 'var(--text-muted)', fontSize: 12 }}>{iv.invoice} · S${Number(iv.total).toFixed(2)} · deleted {new Date(iv.deleted_at).toLocaleDateString('en-GB')}</div>)}
                </section>
              )}
            </div>
          )}
        </Modal>
      )}
      {creditForm && (
        <Modal title={creditForm.mode === 'legacy' ? 'Opening credit balance' : 'Adjust credit'} maxWidth={460}
          onClose={() => setCreditForm(null)}
          footer={<><button className="btn btn-secondary" onClick={() => setCreditForm(null)}>Cancel</button>
            <button className="btn btn-primary" onClick={submitCredit} disabled={creditBusy}>{creditBusy ? 'Saving…' : 'Confirm'}</button></>}>
          <div className="form-grid">
            <div style={{ fontSize: 12.5, color: 'var(--text-secondary)' }}>
              {creditForm.mode === 'legacy'
                ? 'Records an old-client balance. This creates no commission and cannot be edited afterwards.'
                : 'Posts a correcting entry. Nothing already recorded is altered.'}
            </div>
            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 10 }}>
              <div className="form-group" style={{ marginBottom: 0 }}>
                <label>Category *</label>
                <select value={creditForm.category} onChange={e => setCreditForm((f: any) => ({ ...f, category: e.target.value }))}>
                  <option value="paid">Paid</option>
                  <option value="bonus">Bonus</option>
                  <option value="legacy">Legacy</option>
                  {creditForm.mode === 'adjust' && <><option value="promotional">Promotional / FOC</option><option value="exchange">Exchange</option></>}
                </select>
              </div>
              {creditForm.mode === 'adjust' && (
                <div className="form-group" style={{ marginBottom: 0 }}>
                  <label>Direction *</label>
                  <select value={creditForm.direction} onChange={e => setCreditForm((f: any) => ({ ...f, direction: e.target.value }))}>
                    <option value="increase">Increase</option>
                    <option value="decrease">Decrease</option>
                  </select>
                </div>
              )}
              <div className="form-group" style={{ marginBottom: 0 }}>
                <label>Amount (S$) *</label>
                <input type="number" min={0} step={0.01} value={creditForm.amount} onChange={e => setCreditForm((f: any) => ({ ...f, amount: e.target.value }))} autoFocus />
              </div>
              <div className="form-group" style={{ marginBottom: 0 }}>
                <label>Store {creditForm.mode === 'legacy' ? '*' : ''}</label>
                <select value={creditForm.store_id} onChange={e => setCreditForm((f: any) => ({ ...f, store_id: e.target.value }))}>
                  <option value="">— Select —</option>
                  {creditStores.map(s2 => <option key={s2.id} value={s2.id}>{s2.name}</option>)}
                </select>
              </div>
              {creditForm.mode === 'legacy' && (
                <div className="form-group" style={{ marginBottom: 0 }}>
                  <label>Original purchase date *</label>
                  <input type="date" value={creditForm.purchase_date} onChange={e => setCreditForm((f: any) => ({ ...f, purchase_date: e.target.value }))} />
                </div>
              )}
              <div className="form-group" style={{ marginBottom: 0 }}>
                <label>Effective date</label>
                <input type="date" value={creditForm.effective_date} onChange={e => setCreditForm((f: any) => ({ ...f, effective_date: e.target.value }))} />
              </div>
              <div className="form-group" style={{ marginBottom: 0 }}>
                <label>Reference number</label>
                <input value={creditForm.reference_no} onChange={e => setCreditForm((f: any) => ({ ...f, reference_no: e.target.value }))} placeholder="Optional — must be unique if given" />
              </div>
            </div>
            {creditForm.mode === 'adjust' && (
              <div className="form-group" style={{ marginBottom: 0 }}>
                <label>Reason *</label>
                <input value={creditForm.reason} onChange={e => setCreditForm((f: any) => ({ ...f, reason: e.target.value }))} />
              </div>
            )}
            <div className="form-group" style={{ marginBottom: 0 }}>
              <label>Supporting note {creditForm.mode === 'legacy' ? '*' : ''}</label>
              <textarea rows={2} value={creditForm.note} onChange={e => setCreditForm((f: any) => ({ ...f, note: e.target.value }))} />
            </div>
            {creditErr && <div className="alert alert-danger" style={{ marginBottom: 0 }}><span>⚠</span><div>{creditErr}</div></div>}
          </div>
        </Modal>
      )}

      {srcFor && (
        <Modal title={`Customer Source — ${srcFor.full_name}`} maxWidth={420} onClose={() => setSrcFor(null)}
          footer={<>
            <button className="btn btn-secondary" onClick={() => setSrcFor(null)}>Cancel</button>
            <button className="btn btn-primary" disabled={srcBusy || !srcOptId} onClick={async () => {
              setSrcBusy(true); setSrcErr(null);
              const { error } = await supabase.rpc('set_customer_source', {
                p_customer_id: srcFor.id, p_option_id: srcOptId,
                p_details: srcDetails.trim() || null, p_reason: srcReason.trim() || null,
              });
              setSrcBusy(false);
              if (error) { setSrcErr(error.message); return; }
              setSrcFor(null); load();
            }}>{srcBusy ? 'Saving…' : 'Save Source'}</button>
          </>}>
          <div className="form-grid">
            {srcErr && <div className="alert alert-danger" style={{ fontSize: 12.5 }}>{srcErr}</div>}
            <div style={{ fontSize: 12, color: 'var(--text-muted)' }}>
              This updates the customer's <b>current</b> source. Health-survey snapshots are permanent and stay unchanged; the change is audit-logged.
            </div>
            <div>
              <label>Source</label>
              <select value={srcOptId} onChange={e => { setSrcOptId(e.target.value); setSrcDetails(''); }}>
                <option value="">— Select —</option>
                {sourceOpts.map(o => <option key={o.id} value={o.id}>{o.label}</option>)}
              </select>
            </div>
            {sourceOpts.find(o => o.id === srcOptId)?.requires_details && (
              <div><label>Details <span style={{ color: 'var(--danger)' }}>*</span></label>
                <input value={srcDetails} onChange={e => setSrcDetails(e.target.value)} /></div>
            )}
            <div><label>Reason for change</label>
              <input value={srcReason} onChange={e => setSrcReason(e.target.value)} placeholder="Optional — shown in the audit log" /></div>
          </div>
        </Modal>
      )}

      {phoneFor && (
        <Modal title={`Change Phone — ${phoneFor.full_name}`} maxWidth={420} onClose={() => setPhoneFor(null)}
          footer={<><button className="btn btn-secondary" onClick={() => setPhoneFor(null)}>Cancel</button><button className="btn btn-primary" onClick={submitPhoneChange} disabled={phoneBusy}>{phoneBusy ? 'Saving…' : 'Change Number'}</button></>}>
          <div className="form-grid">
            {phoneErr && <div className="alert alert-danger" style={{ marginBottom: 0 }}><span>⚠</span><div>{phoneErr}</div></div>}
            <div style={{ fontSize: 13, color: 'var(--text-secondary)' }}>Current number: <strong>{phoneFor.phone}</strong> — it will move into this customer's phone history.</div>
            <div className="form-group"><label>New Phone Number *</label><input value={newPhone} onChange={e => setNewPhone(e.target.value)} placeholder="e.g. 91234567" autoFocus /></div>
            <div className="form-group"><label>Reason *</label><input value={phoneReason} onChange={e => setPhoneReason(e.target.value)} placeholder="Why is the number changing?" /></div>
          </div>
        </Modal>
      )}

      {profileFor && (
        <Modal title={`Profile — ${profileFor.full_name}`} maxWidth={460} onClose={() => setProfileFor(null)}
          footer={<button className="btn btn-secondary" onClick={() => setProfileFor(null)}>Close</button>}>
          {!profileStats ? <div className="empty-state"><RefreshCw size={22} className="spin" style={{ opacity: 0.4 }} /></div> : (
            <div className="form-grid">
              {canComplete ? (
                <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 10 }}>
                  <div style={{ padding: 12, background: 'var(--surface-2)', borderRadius: 'var(--radius-sm)' }}>
                    <div style={{ fontSize: 11, color: 'var(--text-muted)' }}>Paid purchases</div>
                    <div style={{ fontSize: 20, fontWeight: 700 }}>{profileStats.purchases ?? 0}</div>
                  </div>
                  <div style={{ padding: 12, background: 'var(--surface-2)', borderRadius: 'var(--radius-sm)' }}>
                    <div style={{ fontSize: 11, color: 'var(--text-muted)' }}>Total spend</div>
                    <div style={{ fontSize: 20, fontWeight: 700 }}>S${Number(profileStats.total_spend ?? 0).toFixed(2)}</div>
                  </div>
                  <div style={{ padding: 12, background: 'var(--surface-2)', borderRadius: 'var(--radius-sm)' }}>
                    <div style={{ fontSize: 11, color: 'var(--text-muted)' }}>Customers referred</div>
                    <div style={{ fontSize: 20, fontWeight: 700 }}>{profileStats.referred_count ?? 0}</div>
                  </div>
                  <div style={{ padding: 12, background: 'var(--surface-2)', borderRadius: 'var(--radius-sm)' }}>
                    <div style={{ fontSize: 11, color: 'var(--text-muted)' }}>Referred by</div>
                    <div style={{ fontSize: 14, fontWeight: 600, marginTop: 4 }}>{profileStats.referrer_name ?? '—'}</div>
                  </div>
                </div>
              ) : (
                <div className="alert alert-info" style={{ marginBottom: 0 }}><span>ℹ️</span><div>Limited view — financial, commission, and audit history are visible to Owners and Managers only.</div></div>
              )}
              <div style={{ fontSize: 12, color: 'var(--text-secondary)', display: 'flex', flexWrap: 'wrap', gap: '4px 14px' }}>
                <span>Phone: {profileFor.phone}</span>
                {profileFor.email && <span>· {profileFor.email}</span>}
                {profileFor.date_of_birth && <span>· DOB: {new Date(profileFor.date_of_birth).toLocaleDateString()}</span>}
                {profileFor.gender && <span>· {profileFor.gender === 'other' ? (profileFor.gender_other || 'Other') : (profileFor.gender.charAt(0).toUpperCase() + profileFor.gender.slice(1))}</span>}
                {profileFor.occupation && <span>· {profileFor.occupation}</span>}
              </div>
              {canComplete && (() => {
                const hist = phoneHistory.filter(h => h.customer_id === profileFor.id).sort((a, b) => b.created_at.localeCompare(a.created_at));
                return hist.length > 0 ? (
                  <div>
                    <label>Phone history</label>
                    <div style={{ display: 'flex', flexDirection: 'column', gap: 4, marginTop: 4 }}>
                      {hist.map((h, i) => (
                        <div key={i} style={{ fontSize: 12, color: 'var(--text-secondary)', display: 'flex', justifyContent: 'space-between', borderBottom: '1px solid var(--border)', paddingBottom: 3 }}>
                          <span style={{ fontFamily: 'var(--font-display)' }}>{h.phone}</span>
                          <span style={{ color: 'var(--text-muted)' }}>{h.reason || '—'} · {new Date(h.created_at).toLocaleDateString()}</span>
                        </div>
                      ))}
                    </div>
                  </div>
                ) : null;
              })()}
              {canComplete && timeline && timeline.length > 0 && (
                <div>
                  <label>Purchase timeline</label>
                  <div style={{ display: 'flex', flexDirection: 'column', gap: 6, marginTop: 6 }}>
                    {timeline.map((inv: any) => {
                      const open = !!expandedInv[inv.invoice_id];
                      const statusCls = inv.status === 'paid' ? 'badge-success' : inv.status === 'unpaid' ? 'badge-accent' : inv.status === 'cancelled' || inv.status === 'refunded' ? 'badge-danger' : 'badge-muted';
                      return (
                        <div key={inv.invoice_id} style={{ border: '1px solid var(--border)', borderRadius: 'var(--radius-sm)', overflow: 'hidden' }}>
                          <div onClick={() => setExpandedInv(s => ({ ...s, [inv.invoice_id]: !s[inv.invoice_id] }))}
                            style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '8px 10px', cursor: 'pointer', background: 'var(--surface-2)' }}>
                            <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                              {open ? <ChevronDown size={14} /> : <ChevronRight size={14} />}
                              <span style={{ fontWeight: 600, fontSize: 13 }}>{inv.invoice_no}</span>
                              {inv.is_topup && <span className="badge badge-muted" style={{ fontSize: 10 }}>top-up</span>}
                              <span style={{ fontSize: 11.5, color: 'var(--text-muted)' }}>{inv.date ? new Date(inv.date).toLocaleDateString('en-GB') : '—'}</span>
                            </div>
                            <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                              <span className={`badge ${statusCls}`} style={{ fontSize: 10, textTransform: 'capitalize' }}>{inv.status}</span>
                              <span style={{ fontWeight: 700, fontSize: 13 }}>S${Number(inv.total).toFixed(2)}</span>
                            </div>
                          </div>
                          {open && (
                            <div style={{ padding: '6px 10px 8px 30px' }}>
                              {(inv.items ?? []).map((it: any, j: number) => (
                                <div key={j} style={{ display: 'flex', justifyContent: 'space-between', fontSize: 12, padding: '3px 0', borderBottom: j < inv.items.length - 1 ? '1px solid var(--border)' : 'none' }}>
                                  <span>
                                    <span style={{ color: 'var(--text-muted)', textTransform: 'capitalize' }}>{String(it.kind).replace('_', ' ')}</span> · {it.name}
                                    {it.qty > 1 && <span style={{ color: 'var(--text-muted)' }}> ×{it.qty}</span>}
                                  </span>
                                  <span style={{ fontWeight: 600 }}>S${Number(it.line_total).toFixed(2)}</span>
                                </div>
                              ))}
                              {Number(inv.save_earth) > 0 && <div style={{ fontSize: 11.5, color: 'var(--text-muted)', marginTop: 4 }}>🌱 Save Earth: S${Number(inv.save_earth).toFixed(2)}</div>}
                            </div>
                          )}
                        </div>
                      );
                    })}
                  </div>
                </div>
              )}
              {canComplete && timeline && timeline.length === 0 && (
                <div style={{ fontSize: 12.5, color: 'var(--text-muted)' }}>No purchases yet.</div>
              )}
            </div>
          )}
        </Modal>
      )}
    </div>
  );
};

export default CustomersPage;
