import React, { useCallback, useEffect, useMemo, useState } from 'react';
import { supabase } from '../lib/supabase';
import { useAuth } from '../context/AuthContext';
import { isManagerOrAbove } from '../types';
import { Modal, RoleGate } from '../components/ui';
import {
  Plus, Pencil, Archive, Search, RefreshCw, Sparkles, Store as StoreIcon,
  Ticket, Clock, AlertTriangle,
} from 'lucide-react';
import { describeFrequency } from '../lib/therapy/frequency.mjs';
import '../components/therapy/therapy.css';

/*
 * The therapy service catalogue: what a single session IS, what it costs where,
 * and how often it may be taken — and, on the second tab, what a therapy voucher
 * entitles its holder to.
 *
 * The frequency rule is entered as structured fields, never as free text,
 * because the database enforces those fields. The sentence under the inputs is
 * generated from them by the same function the server uses, so what the manager
 * reads while typing is what will be enforced.
 */

type FrequencyKind = 'per_day' | 'per_week' | 'per_month' | 'per_hours' | 'unrestricted';

interface CatalogueRow {
  id: string; service_code: string; name: string; description: string | null;
  standard_price: number; effective_price: number; duration_minutes: number | null;
  frequency_kind: FrequencyKind; frequency_max_per_period: number;
  frequency_interval_hours: number | null; frequency_description: string;
  is_active: boolean; is_archived: boolean;
  store_count: number; store_names: string[] | null;
  available_here: boolean; has_price_override: boolean; can_manage: boolean;
}

interface StoreRow { id: string; name: string; }
interface VoucherRow { id: string; name: string; code: string | null; }

interface ServiceForm {
  service_code: string; name: string; description: string;
  standard_price: string; duration_minutes: string;
  frequency_kind: FrequencyKind; frequency_max_per_period: string;
  frequency_interval_hours: string; is_active: boolean; notes: string;
}

const blankService = (r?: CatalogueRow): ServiceForm => ({
  service_code: r?.service_code ?? '', name: r?.name ?? '', description: r?.description ?? '',
  standard_price: r ? String(r.standard_price) : '',
  duration_minutes: r?.duration_minutes != null ? String(r.duration_minutes) : '',
  frequency_kind: r?.frequency_kind ?? 'unrestricted',
  frequency_max_per_period: r ? String(r.frequency_max_per_period) : '1',
  frequency_interval_hours: r?.frequency_interval_hours != null ? String(r.frequency_interval_hours) : '',
  is_active: r?.is_active ?? false, notes: '',
});

/** One requirement in a voucher: a fixed service, or a choice between several. */
interface Component {
  kind: 'fixed' | 'choice';
  quantity: string;
  service_id: string;
  service_ids: string[];
  label: string;
}
const blankComponent = (kind: Component['kind']): Component =>
  ({ kind, quantity: '1', service_id: '', service_ids: [], label: '' });

const money = (n: number | null | undefined) =>
  n == null ? '—' : `S$${Number(n).toFixed(2)}`;

const TherapyServicesPage: React.FC = () => {
  const { profile } = useAuth();
  const canManage = isManagerOrAbove(profile?.role);

  const [tab, setTab] = useState<'services' | 'vouchers'>('services');
  const [loading, setLoading] = useState(true);
  const [rows, setRows] = useState<CatalogueRow[]>([]);
  const [stores, setStores] = useState<StoreRow[]>([]);
  const [vouchers, setVouchers] = useState<VoucherRow[]>([]);
  const [err, setErr] = useState<string | null>(null);

  const [search, setSearch] = useState('');
  const [status, setStatus] = useState<'active' | 'draft' | 'archived' | 'all'>('active');
  const [storeFilter, setStoreFilter] = useState<string>('');

  const load = useCallback(async () => {
    setLoading(true);
    const [cat, st, vc] = await Promise.all([
      supabase.rpc('therapy_service_catalogue', {
        p_store_id: storeFilter || null, p_include_inactive: true,
      }),
      supabase.from('stores').select('id,name').order('name'),
      supabase.from('vouchers').select('id,name,code').is('deleted_at', null)
        .eq('is_active', true).order('name'),
    ]);
    // A failed RPC and an empty catalogue look identical unless the error is
    // read. Showing "no services" when the call was refused sends someone
    // looking for the wrong problem.
    if (cat.error) setErr(cat.error.message); else setErr(null);
    setRows((cat.data as CatalogueRow[]) ?? []);
    setStores((st.data as StoreRow[]) ?? []);
    setVouchers((vc.data as VoucherRow[]) ?? []);
    setLoading(false);
  }, [storeFilter]);

  useEffect(() => { load(); }, [load]);

  const filtered = useMemo(() => rows.filter(r => {
    const q = search.trim().toLowerCase();
    const matchQ = !q || r.name.toLowerCase().includes(q)
      || (r.service_code ?? '').toLowerCase().includes(q)
      || (r.description ?? '').toLowerCase().includes(q);
    const matchStatus =
      status === 'all' ? true
      : status === 'archived' ? r.is_archived
      : status === 'active' ? (r.is_active && !r.is_archived)
      : (!r.is_active && !r.is_archived);
    return matchQ && matchStatus;
  }), [rows, search, status]);

  // ---------------------------------------------------------------- services
  const [serviceOpen, setServiceOpen] = useState(false);
  const [editing, setEditing] = useState<CatalogueRow | null>(null);
  const [form, setForm] = useState<ServiceForm>(blankService());
  const [saving, setSaving] = useState(false);
  const [formErr, setFormErr] = useState<string | null>(null);

  const openAdd = () => { setEditing(null); setForm(blankService()); setFormErr(null); setServiceOpen(true); };
  const openEdit = (r: CatalogueRow) => { setEditing(r); setForm(blankService(r)); setFormErr(null); setServiceOpen(true); };

  // The same sentence the database generates, computed here so it updates as
  // the fields change.
  const preview = describeFrequency({
    kind: form.frequency_kind,
    max_per_period: Number(form.frequency_max_per_period || 1),
    interval_hours: Number(form.frequency_interval_hours || 0),
  });

  const saveService = async () => {
    setSaving(true); setFormErr(null);
    const { error } = await supabase.rpc('upsert_therapy_service', {
      p_id: editing?.id ?? null,
      p_service_code: form.service_code,
      p_name: form.name,
      p_standard_price: form.standard_price === '' ? null : Number(form.standard_price),
      p_duration_minutes: form.duration_minutes === '' ? null : Number(form.duration_minutes),
      p_frequency_kind: form.frequency_kind,
      p_frequency_max_per_period: Number(form.frequency_max_per_period || 1),
      p_frequency_interval_hours:
        form.frequency_kind === 'per_hours' && form.frequency_interval_hours !== ''
          ? Number(form.frequency_interval_hours) : null,
      p_description: form.description || null,
      p_is_active: form.is_active,
      p_notes: form.notes || null,
    });
    setSaving(false);
    if (error) { setFormErr(error.message); return; }
    setServiceOpen(false);
    await load();
  };

  const archive = async (r: CatalogueRow) => {
    if (!window.confirm(`Archive "${r.name}"? It stops being sellable and stays readable on past invoices and issued vouchers.`)) return;
    const { error } = await supabase.rpc('archive_therapy_service', { p_id: r.id, p_reason: null });
    if (error) { setErr(error.message); return; }
    await load();
  };

  // ------------------------------------------------------------ store prices
  const [storeOpen, setStoreOpen] = useState<CatalogueRow | null>(null);
  const [storeRows, setStoreRows] = useState<Record<string, { available: boolean; override: string }>>({});
  const [storeSaving, setStoreSaving] = useState(false);

  const openStores = async (r: CatalogueRow) => {
    const { data } = await supabase.from('therapy_service_stores')
      .select('store_id,is_available,price_override').eq('service_id', r.id);
    const map: Record<string, { available: boolean; override: string }> = {};
    for (const s of stores) map[s.id] = { available: false, override: '' };
    for (const d of ((data as any[]) ?? [])) {
      map[d.store_id] = {
        available: !!d.is_available,
        override: d.price_override == null ? '' : String(d.price_override),
      };
    }
    setStoreRows(map); setStoreOpen(r);
  };

  const saveStores = async () => {
    if (!storeOpen) return;
    setStoreSaving(true);
    for (const s of stores) {
      const row = storeRows[s.id];
      const { error } = await supabase.rpc('set_therapy_service_store', {
        p_service_id: storeOpen.id, p_store_id: s.id,
        p_is_available: row?.available ?? false,
        p_price_override: row?.override === '' || row?.override == null ? null : Number(row.override),
      });
      if (error) { setStoreSaving(false); setErr(error.message); return; }
    }
    setStoreSaving(false); setStoreOpen(null); await load();
  };

  // ---------------------------------------------------------------- vouchers
  const [voucherId, setVoucherId] = useState('');
  const [definition, setDefinition] = useState<any>(null);
  const [components, setComponents] = useState<Component[]>([]);
  const [validityKind, setValidityKind] = useState<'none' | 'days' | 'months'>('none');
  const [validityValue, setValidityValue] = useState('');
  const [repeatKind, setRepeatKind] = useState<FrequencyKind>('unrestricted');
  const [repeatMax, setRepeatMax] = useState('1');
  const [repeatHours, setRepeatHours] = useState('');
  const [defSaving, setDefSaving] = useState(false);
  const [defErr, setDefErr] = useState<string | null>(null);
  const [defSaved, setDefSaved] = useState(false);

  const loadDefinition = useCallback(async (id: string) => {
    setDefErr(null); setDefSaved(false);
    if (!id) { setDefinition(null); setComponents([]); return; }
    const { data, error } = await supabase.rpc('therapy_voucher_definition', { p_voucher_id: id });
    if (error) { setDefErr(error.message); return; }
    setDefinition(data ?? null);
    if (!data) {
      setComponents([]); setValidityKind('none'); setValidityValue('');
      setRepeatKind('unrestricted'); setRepeatMax('1'); setRepeatHours('');
      return;
    }
    setComponents(((data.components as any[]) ?? []).map(c => ({
      kind: c.component_kind,
      quantity: String(c.quantity),
      service_id: c.component_kind === 'fixed' ? (c.services?.[0]?.service_id ?? '') : '',
      service_ids: c.component_kind === 'choice' ? (c.services ?? []).map((s: any) => s.service_id) : [],
      label: c.label ?? '',
    })));
    setValidityKind(data.validity_kind ?? 'none');
    setValidityValue(data.validity_value == null ? '' : String(data.validity_value));
    setRepeatKind(data.repeat_kind ?? 'unrestricted');
    setRepeatMax(String(data.repeat_max_per_period ?? 1));
    setRepeatHours(data.repeat_interval_hours == null ? '' : String(data.repeat_interval_hours));
  }, []);

  useEffect(() => { loadDefinition(voucherId); }, [voucherId, loadDefinition]);

  const activeServices = rows.filter(r => r.is_active && !r.is_archived);
  const serviceName = (id: string) => rows.find(r => r.id === id)?.name ?? 'Unknown service';

  const saveDefinition = async () => {
    setDefSaving(true); setDefErr(null); setDefSaved(false);
    const { error } = await supabase.rpc('upsert_therapy_voucher_definition', {
      p_voucher_id: voucherId,
      p_components: components.map(c => c.kind === 'fixed'
        ? { kind: 'fixed', quantity: Number(c.quantity || 1), service_id: c.service_id, label: c.label || null }
        : { kind: 'choice', quantity: Number(c.quantity || 1), service_ids: c.service_ids, label: c.label || null }),
      p_validity_kind: validityKind,
      p_validity_value: validityKind === 'none' || validityValue === '' ? null : Number(validityValue),
      p_repeat_kind: repeatKind,
      p_repeat_max_per_period: Number(repeatMax || 1),
      p_repeat_interval_hours: repeatKind === 'per_hours' && repeatHours !== '' ? Number(repeatHours) : null,
      p_terms: null,
    });
    setDefSaving(false);
    if (error) { setDefErr(error.message); return; }
    setDefSaved(true);
    await loadDefinition(voucherId);
  };

  const clearDefinition = async () => {
    if (!window.confirm('Remove the therapy contents of this voucher? Vouchers already issued keep the rights they were given.')) return;
    const { error } = await supabase.rpc('clear_therapy_voucher_definition', { p_voucher_id: voucherId });
    if (error) { setDefErr(error.message); return; }
    await loadDefinition(voucherId);
  };

  if (!canManage) {
    return (
      <div>
        <div className="page-header"><div><h2>Therapy Services</h2></div></div>
        <div className="card" style={{ padding: 20 }}>
          <p>Only an Owner or Manager can manage the therapy service catalogue.</p>
        </div>
      </div>
    );
  }

  return (
    <div>
      <div className="page-header">
        <div>
          <h2>Therapy Services</h2>
          <p>
            What one therapy session is, what it costs at each store, and how often it may be
            taken. Unlimited-therapy packages are separate and stay on the Therapy page.
          </p>
        </div>
        <div style={{ display: 'flex', gap: 10 }}>
          <button className="btn btn-secondary" onClick={load}>
            <RefreshCw size={15} className={loading ? 'spin' : ''} /> Refresh
          </button>
          {tab === 'services' && (
            <RoleGate allow={isManagerOrAbove}>
              <button className="btn btn-primary" onClick={openAdd}><Plus size={16} /> Add Service</button>
            </RoleGate>
          )}
        </div>
      </div>

      {err && <div className="alert alert-danger"><span>⚠</span><div>{err}</div></div>}

      <div className="therapy-tabs">
        <button className={`therapy-tab ${tab === 'services' ? 'active' : ''}`} onClick={() => setTab('services')}>
          <Sparkles size={15} /> Services
        </button>
        <button className={`therapy-tab ${tab === 'vouchers' ? 'active' : ''}`} onClick={() => setTab('vouchers')}>
          <Ticket size={15} /> What a voucher gives
        </button>
      </div>

      {tab === 'services' && (
        <>
          <div className="therapy-filters">
            <div className="therapy-search">
              <Search size={15} className="therapy-search-icon" />
              <input value={search} onChange={e => setSearch(e.target.value)}
                placeholder="Search name, code or description…" />
            </div>
            <div className="therapy-filter-group">
              {(['active', 'draft', 'archived', 'all'] as const).map(s => (
                <button key={s} className={`btn btn-sm ${status === s ? 'btn-primary' : 'btn-secondary'}`}
                  onClick={() => setStatus(s)}>
                  {s === 'active' ? 'Active' : s === 'draft' ? 'Not active' : s === 'archived' ? 'Archived' : 'All'}
                </button>
              ))}
            </div>
            <select value={storeFilter} onChange={e => setStoreFilter(e.target.value)}
              className="therapy-store-select"
              title="Show the price and availability at one store">
              <option value="">Every store (standard price)</option>
              {stores.map(s => <option key={s.id} value={s.id}>{s.name}</option>)}
            </select>
          </div>

          <div className="card">
            <div className="table-wrap">
              {loading ? (
                <div className="empty-state">
                  <RefreshCw size={26} className="spin" style={{ opacity: 0.4 }} />
                  <p style={{ marginTop: 10 }}>Loading services…</p>
                </div>
              ) : filtered.length === 0 ? (
                <div className="empty-state">
                  <Sparkles size={36} style={{ opacity: 0.3, marginBottom: 10 }} />
                  <p style={{ fontWeight: 600 }}>No therapy services here</p>
                  <p style={{ fontSize: 13 }}>
                    {rows.length === 0
                      ? 'Add the services you sell — for example Power Recharge and Foot Detox.'
                      : 'Nothing matches this search or filter.'}
                  </p>
                </div>
              ) : (
                <table className="therapy-summary-table">
                  <thead>
                    <tr>
                      <th>Service</th>
                      <th>Duration</th>
                      <th className="therapy-num">{storeFilter ? 'Price here' : 'Standard price'}</th>
                      <th className="therapy-hide-mobile">How often</th>
                      <th className="therapy-hide-mobile">Stores</th>
                      <th>Status</th>
                      <th></th>
                    </tr>
                  </thead>
                  <tbody>
                    {filtered.map(r => (
                      <tr key={r.id}>
                        <td className="therapy-service-cell">
                          <strong>{r.name}</strong>
                          <div className="therapy-cell-sub">{r.service_code}</div>
                          {r.description && <div className="therapy-cell-sub">{r.description}</div>}
                          {/* On a phone the frequency column is hidden, so the rule
                              moves here rather than disappearing. */}
                          <div className="therapy-cell-sub therapy-only-mobile">
                            {r.frequency_description}
                            {r.store_count === 0 ? ' · Offered nowhere' : ` · ${r.store_count} store(s)`}
                          </div>
                        </td>
                        <td>
                          {r.duration_minutes == null
                            ? <span className="therapy-chip therapy-chip-warn">No duration</span>
                            : <><Clock size={12} style={{ verticalAlign: -2, marginRight: 4 }} />{r.duration_minutes} min</>}
                        </td>
                        <td className="therapy-num">
                          {money(storeFilter ? r.effective_price : r.standard_price)}
                          {storeFilter && r.has_price_override &&
                            <div className="therapy-cell-sub">overrides {money(r.standard_price)}</div>}
                        </td>
                        <td className="therapy-hide-mobile" style={{ maxWidth: 260 }}>
                          <span className="therapy-cell-sub">{r.frequency_description}</span>
                        </td>
                        <td className="therapy-hide-mobile">
                          {r.store_count === 0
                            ? <span className="therapy-chip therapy-chip-warn">Nowhere</span>
                            : <span title={(r.store_names ?? []).join(', ')}>{r.store_count}</span>}
                        </td>
                        <td>
                          {r.is_archived ? <span className="badge badge-muted">Archived</span>
                            : r.is_active ? <span className="badge badge-success">Active</span>
                            : <span className="badge badge-muted">Not active</span>}
                        </td>
                        <td>
                          <div style={{ display: 'flex', gap: 4 }}>
                            <button className="btn btn-secondary btn-sm btn-icon" title="Edit"
                              onClick={() => openEdit(r)} disabled={r.is_archived}><Pencil size={13} /></button>
                            <button className="btn btn-secondary btn-sm btn-icon" title="Stores and prices"
                              onClick={() => openStores(r)} disabled={r.is_archived}><StoreIcon size={13} /></button>
                            <button className="btn btn-danger btn-sm btn-icon" title="Archive"
                              onClick={() => archive(r)} disabled={r.is_archived}><Archive size={13} /></button>
                          </div>
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              )}
            </div>
          </div>
        </>
      )}

      {tab === 'vouchers' && (
        <div className="card" style={{ padding: 20 }}>
          <div className="alert alert-info">
            <span>ℹ️</span>
            <div>
              A voucher can give a fixed session, a choice between services, or a combination of
              both. What is set here applies to vouchers issued <strong>from now on</strong> —
              vouchers already in a customer's hands keep the terms they were given.
            </div>
          </div>

          <div className="form-grid">
            <div className="form-group">
              <label>Voucher</label>
              <select value={voucherId} onChange={e => setVoucherId(e.target.value)}>
                <option value="">Choose a voucher…</option>
                {vouchers.map(v => (
                  <option key={v.id} value={v.id}>{v.name}{v.code ? ` (${v.code})` : ''}</option>
                ))}
              </select>
            </div>
          </div>

          {voucherId && (
            <>
              {definition && (
                <div className="therapy-definition-current">
                  <strong>Currently gives:</strong> {definition.components?.length
                    ? `${definition.sessions_per_voucher} session(s)` : 'nothing yet'}
                  {definition.version > 1 && <span className="therapy-chip" style={{ marginLeft: 8 }}>
                    edited {definition.version - 1} time(s)</span>}
                </div>
              )}

              <h4 style={{ marginTop: 18 }}>Contents</h4>
              {components.length === 0 && (
                <p className="therapy-cell-sub">
                  Nothing yet. Add a fixed session or a choice — a voucher is the sum of what you add here.
                </p>
              )}

              {components.map((c, i) => (
                <div key={i} className="therapy-component">
                  <div className="therapy-component-head">
                    <span className="therapy-chip">{c.kind === 'fixed' ? 'Fixed session' : 'Choice'}</span>
                    <button className="btn btn-danger btn-sm"
                      onClick={() => setComponents(components.filter((_, j) => j !== i))}>Remove</button>
                  </div>
                  <div className="therapy-component-body">
                    <div className="form-group" style={{ maxWidth: 110 }}>
                      <label>How many</label>
                      <input type="number" min={1} value={c.quantity}
                        onChange={e => setComponents(components.map((x, j) =>
                          j === i ? { ...x, quantity: e.target.value } : x))} />
                    </div>
                    {c.kind === 'fixed' ? (
                      <div className="form-group" style={{ flex: 1, minWidth: 220 }}>
                        <label>Of which service</label>
                        <select value={c.service_id}
                          onChange={e => setComponents(components.map((x, j) =>
                            j === i ? { ...x, service_id: e.target.value } : x))}>
                          <option value="">Choose…</option>
                          {activeServices.map(s => <option key={s.id} value={s.id}>{s.name}</option>)}
                        </select>
                      </div>
                    ) : (
                      <div className="form-group" style={{ flex: 1, minWidth: 220 }}>
                        <label>Chosen from</label>
                        <div className="therapy-checkboxes">
                          {activeServices.map(s => (
                            <label key={s.id} className="therapy-checkbox">
                              <input type="checkbox" checked={c.service_ids.includes(s.id)}
                                onChange={e => setComponents(components.map((x, j) => j === i
                                  ? { ...x, service_ids: e.target.checked
                                      ? [...x.service_ids, s.id]
                                      : x.service_ids.filter(id => id !== s.id) }
                                  : x))} />
                              {s.name}
                            </label>
                          ))}
                        </div>
                      </div>
                    )}
                  </div>
                  <div className="therapy-component-reads">
                    Reads as: {c.kind === 'fixed'
                      ? `${c.quantity || 1} x ${c.service_id ? serviceName(c.service_id) : 'a service'}`
                      : `${c.quantity || 1} x chosen from ${c.service_ids.length
                          ? c.service_ids.map(serviceName).sort().join(' or ')
                          : 'no service yet'}`}
                  </div>
                </div>
              ))}

              <div style={{ display: 'flex', gap: 8, marginTop: 10, flexWrap: 'wrap' }}>
                <button className="btn btn-secondary btn-sm"
                  onClick={() => setComponents([...components, blankComponent('fixed')])}>
                  <Plus size={13} /> Fixed session
                </button>
                <button className="btn btn-secondary btn-sm"
                  onClick={() => setComponents([...components, blankComponent('choice')])}>
                  <Plus size={13} /> Choice of services
                </button>
              </div>

              <h4 style={{ marginTop: 22 }}>Validity and repeat</h4>
              <div className="therapy-inline-fields">
                <div className="form-group" style={{ minWidth: 180 }}>
                  <label>Expires</label>
                  <select value={validityKind} onChange={e => setValidityKind(e.target.value as any)}>
                    <option value="none">No expiry of its own</option>
                    <option value="days">A number of days after issue</option>
                    <option value="months">A number of months after issue</option>
                  </select>
                </div>
                {validityKind !== 'none' && (
                  <div className="form-group" style={{ maxWidth: 130 }}>
                    <label>{validityKind === 'days' ? 'Days' : 'Months'}</label>
                    <input type="number" min={1} value={validityValue}
                      onChange={e => setValidityValue(e.target.value)} />
                  </div>
                )}
                <div className="form-group" style={{ minWidth: 200 }}>
                  <label>How often it may be used</label>
                  <select value={repeatKind} onChange={e => setRepeatKind(e.target.value as FrequencyKind)}>
                    <option value="unrestricted">No limit of its own</option>
                    <option value="per_day">Per calendar day</option>
                    <option value="per_week">Per calendar week</option>
                    <option value="per_month">Per calendar month</option>
                    <option value="per_hours">Every so many hours</option>
                  </select>
                </div>
                {repeatKind !== 'unrestricted' && (
                  <div className="form-group" style={{ maxWidth: 110 }}>
                    <label>At most</label>
                    <input type="number" min={1} value={repeatMax} onChange={e => setRepeatMax(e.target.value)} />
                  </div>
                )}
                {repeatKind === 'per_hours' && (
                  <div className="form-group" style={{ maxWidth: 130 }}>
                    <label>Every (hours)</label>
                    <input type="number" min={0.5} step={0.5} value={repeatHours}
                      onChange={e => setRepeatHours(e.target.value)} />
                  </div>
                )}
              </div>
              <p className="therapy-cell-sub" style={{ marginTop: 4 }}>
                {describeFrequency({
                  kind: repeatKind,
                  max_per_period: Number(repeatMax || 1),
                  interval_hours: Number(repeatHours || 0),
                })}
                {' '}Each service also has its own limit, and the stricter of the two applies.
              </p>

              {defErr && <div className="alert alert-danger" style={{ marginTop: 12 }}>
                <span>⚠</span><div>{defErr}</div></div>}
              {defSaved && <div className="alert alert-success" style={{ marginTop: 12 }}>
                <span>✓</span><div>Saved. Vouchers issued from now on carry these terms.</div></div>}

              <div style={{ display: 'flex', gap: 8, marginTop: 16 }}>
                <button className="btn btn-primary" onClick={saveDefinition} disabled={defSaving}>
                  {defSaving ? 'Saving…' : 'Save what this voucher gives'}
                </button>
                {definition && (
                  <button className="btn btn-secondary" onClick={clearDefinition}>
                    Make it an ordinary voucher
                  </button>
                )}
              </div>
            </>
          )}
        </div>
      )}

      {serviceOpen && (
        <Modal
          title={editing ? `Edit ${editing.name}` : 'Add Therapy Service'}
          maxWidth={560}
          onClose={() => setServiceOpen(false)}
          footer={<>
            <button className="btn btn-secondary" onClick={() => setServiceOpen(false)}>Cancel</button>
            <button className="btn btn-primary" onClick={saveService} disabled={saving}>
              {saving ? 'Saving…' : editing ? 'Save Changes' : 'Add Service'}
            </button>
          </>}
        >
          <div className="form-grid">
            {formErr && <div className="alert alert-danger" style={{ marginBottom: 0 }}>
              <span>⚠</span><div>{formErr}</div></div>}

            <div className="form-group">
              <label>Name *</label>
              <input value={form.name} onChange={e => setForm({ ...form, name: e.target.value })}
                placeholder="Power Recharge" />
            </div>
            <div className="form-group">
              <label>Code *</label>
              <input value={form.service_code} onChange={e => setForm({ ...form, service_code: e.target.value })}
                placeholder="PR" />
            </div>
            <div className="form-group">
              <label>Standard price (S$) *</label>
              <input type="number" min={0} step="0.01" value={form.standard_price}
                onChange={e => setForm({ ...form, standard_price: e.target.value })} />
              <small>The normal selling price. A store that charges differently is set under Stores.</small>
            </div>
            <div className="form-group">
              <label>Duration (minutes)</label>
              <input type="number" min={1} value={form.duration_minutes}
                onChange={e => setForm({ ...form, duration_minutes: e.target.value })} />
              <small>Required before the service can be made active.</small>
            </div>
            <div className="form-group" style={{ gridColumn: '1 / -1' }}>
              <label>Description</label>
              <input value={form.description} onChange={e => setForm({ ...form, description: e.target.value })} />
            </div>

            <div className="form-group">
              <label>How often may it be taken?</label>
              <select value={form.frequency_kind}
                onChange={e => setForm({ ...form, frequency_kind: e.target.value as FrequencyKind })}>
                <option value="unrestricted">No limit</option>
                <option value="per_day">Per calendar day</option>
                <option value="per_week">Per calendar week</option>
                <option value="per_month">Per calendar month</option>
                <option value="per_hours">Every so many hours</option>
              </select>
            </div>
            {form.frequency_kind !== 'unrestricted' && (
              <div className="form-group">
                <label>At most</label>
                <input type="number" min={1} value={form.frequency_max_per_period}
                  onChange={e => setForm({ ...form, frequency_max_per_period: e.target.value })} />
              </div>
            )}
            {form.frequency_kind === 'per_hours' && (
              <div className="form-group">
                <label>Every (hours) *</label>
                <input type="number" min={0.5} step={0.5} value={form.frequency_interval_hours}
                  onChange={e => setForm({ ...form, frequency_interval_hours: e.target.value })} />
                <small>Measured from the start of the previous session.</small>
              </div>
            )}
            <div className="form-group" style={{ gridColumn: '1 / -1' }}>
              <div className="therapy-preview"><Clock size={14} /> {preview}</div>
            </div>

            <div className="form-group" style={{ gridColumn: '1 / -1' }}>
              <label className="therapy-checkbox">
                <input type="checkbox" checked={form.is_active}
                  onChange={e => setForm({ ...form, is_active: e.target.checked })} />
                Active — available to sell
              </label>
              {form.is_active && form.duration_minutes === '' && (
                <div className="alert alert-warning" style={{ marginTop: 8 }}>
                  <AlertTriangle size={15} />
                  <div>A duration is needed before this can be active.</div>
                </div>
              )}
            </div>
          </div>
        </Modal>
      )}

      {storeOpen && (
        <Modal
          title={`${storeOpen.name} — stores and prices`}
          maxWidth={560}
          onClose={() => setStoreOpen(null)}
          footer={<>
            <button className="btn btn-secondary" onClick={() => setStoreOpen(null)}>Cancel</button>
            <button className="btn btn-primary" onClick={saveStores} disabled={storeSaving}>
              {storeSaving ? 'Saving…' : 'Save'}
            </button>
          </>}
        >
          <p className="therapy-cell-sub">
            Leave a price empty to charge the standard {money(storeOpen.standard_price)}.
            A store with no tick does not offer this service.
          </p>
          <div className="therapy-store-list">
            {stores.map(s => (
              <div key={s.id} className="therapy-store-row">
                <label className="therapy-checkbox">
                  <input type="checkbox" checked={storeRows[s.id]?.available ?? false}
                    onChange={e => setStoreRows({
                      ...storeRows,
                      [s.id]: { available: e.target.checked, override: storeRows[s.id]?.override ?? '' },
                    })} />
                  {s.name}
                </label>
                <input type="number" min={0} step="0.01" placeholder="standard"
                  value={storeRows[s.id]?.override ?? ''}
                  disabled={!(storeRows[s.id]?.available ?? false)}
                  onChange={e => setStoreRows({
                    ...storeRows,
                    [s.id]: { available: storeRows[s.id]?.available ?? false, override: e.target.value },
                  })} />
              </div>
            ))}
          </div>
        </Modal>
      )}
    </div>
  );
};

export default TherapyServicesPage;
