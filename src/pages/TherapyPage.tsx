import React, { useEffect, useState, useCallback } from 'react';
import { supabase } from '../lib/supabase';
import { useAuth } from '../context/AuthContext';
import { Store, Customer, PaymentMethod, TherapyPackageRule, TherapyEntitlement, TherapyBeneficiary, TherapyDateChangeRequest, isOwnerOrManager } from '../types';
import { Modal, NoAccess } from '../components/ui';
import { RefreshCw, Plus, Sparkles, Trash2, Pencil, Users, Search, Phone, Mail, CalendarClock } from 'lucide-react';
import TherapyQualifyModal from '../components/TherapyQualifyModal';
import TherapyEntitlementModal, { statusBadge as benBadge } from '../components/TherapyEntitlementModal';
import TherapyBeneficiaryActions from '../components/TherapyBeneficiaryActions';

const money = (n: number) => `S$${Number(n).toFixed(2)}`;
const sgToday = () => new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Singapore' }); // YYYY-MM-DD

const TherapyPage: React.FC = () => {
  const { profile } = useAuth();
  const canConfig = isOwnerOrManager(profile?.role);
  const [tab, setTab] = useState<'entitlements' | 'beneficiaries' | 'rules'>('entitlements');
  const [benFilter, setBenFilter] = useState<string[]>(['active', 'scheduled']);   // default: live + upcoming
  const [benSearch, setBenSearch] = useState('');
  const [entSearch, setEntSearch] = useState('');
  const [assignFilter, setAssignFilter] = useState<'all' | 'unassigned' | 'partial' | 'complete'>('all');
  const [entInvoices, setEntInvoices] = useState<{ entitlement_id: string; invoice_no: string }[]>([]);
  const [rules, setRules] = useState<TherapyPackageRule[]>([]);
  const [ents, setEnts] = useState<TherapyEntitlement[]>([]);
  const [stores, setStores] = useState<Store[]>([]);
  const [customers, setCustomers] = useState<Customer[]>([]);
  const [methods, setMethods] = useState<PaymentMethod[]>([]);
  const [loading, setLoading] = useState(true);
  const [bens, setBens] = useState<TherapyBeneficiary[]>([]);
  const [dateReqs, setDateReqs] = useState<TherapyDateChangeRequest[]>([]);
  const [manageEnt, setManageEnt] = useState<TherapyEntitlement | null>(null);

  const load = useCallback(async () => {
    setLoading(true);
    const [r, e, s, c, m, b, dc, tei] = await Promise.all([
      supabase.from('therapy_package_rules').select('*').is('deleted_at', null).order('qualifying_amount'),
      supabase.from('therapy_entitlements').select('*').order('created_at', { ascending: false }),
      supabase.from('stores').select('*').is('deleted_at', null).eq('is_active', true).order('name'),
      supabase.from('customers').select('*').is('deleted_at', null),
      supabase.from('payment_methods').select('*').is('deleted_at', null).eq('is_active', true).order('name'),
      supabase.from('therapy_entitlement_beneficiaries').select('*').order('created_at'),
      supabase.from('therapy_date_change_requests').select('*').order('created_at', { ascending: false }),
      supabase.from('therapy_entitlement_invoices').select('entitlement_id,invoice_id'),
    ]);
    setRules((r.data as TherapyPackageRule[]) ?? []);
    setEnts((e.data as TherapyEntitlement[]) ?? []);
    setStores((s.data as Store[]) ?? []);
    setCustomers((c.data as Customer[]) ?? []);
    setMethods((m.data as PaymentMethod[]) ?? []);
    setBens((b.data as TherapyBeneficiary[]) ?? []);
    setDateReqs((dc.data as TherapyDateChangeRequest[]) ?? []);

    // Resolve invoice numbers for the entitlement links (for search).
    const links = (tei.data as any[]) ?? [];
    if (links.length) {
      const ids = [...new Set(links.map(l => l.invoice_id))];
      const { data: invs } = await supabase.from('invoices').select('id,invoice_no').in('id', ids);
      const noById = new Map(((invs as any[]) ?? []).map(i => [i.id, i.invoice_no]));
      setEntInvoices(links.map(l => ({ entitlement_id: l.entitlement_id, invoice_no: noById.get(l.invoice_id) ?? '' })));
    } else {
      setEntInvoices([]);
    }
    setLoading(false);
  }, []);
  useEffect(() => { supabase.rpc('refresh_therapy_statuses').then(() => load()); }, [load]);

  const sName = (id: string) => stores.find(s => s.id === id)?.name ?? '—';
  const cName = (id: string) => customers.find(c => c.id === id)?.full_name ?? '—';

  // How much of an entitlement has been handed to beneficiaries.
  const assignInfo = (e: TherapyEntitlement) => {
    const unlimited = e.entitlement_kind === 'unlimited';
    const total = Number((unlimited ? e.duration_months : e.voucher_qty) ?? 0);
    const used = bens.filter(b => b.entitlement_id === e.id && b.status !== 'cancelled')
      .reduce((s, b) => s + Number((unlimited ? b.portion_months : b.portion_vouchers) ?? 0), 0);
    const state: 'unassigned' | 'partial' | 'complete' = used <= 0 ? 'unassigned' : used >= total ? 'complete' : 'partial';
    return { total, used, state, unit: unlimited ? 'mo' : 'vouchers' };
  };

  // Invoice numbers behind an entitlement. Source invoices are linked to the
  // first entitlement of a qualification, so resolve through the group to
  // cover every package that qualification produced.
  const invoiceNosFor = (e: TherapyEntitlement) => {
    const sameGroup = e.qualification_group_id
      ? ents.filter(x => x.qualification_group_id === e.qualification_group_id).map(x => x.id)
      : [e.id];
    return entInvoices.filter(l => sameGroup.includes(l.entitlement_id)).map(l => l.invoice_no);
  };

  // Shared matcher: customer name / phone / email, entitlement no, invoice no.
  const entMatches = (e: TherapyEntitlement, q: string) => {
    if (!q) return true;
    const cu = customers.find(c => c.id === e.customer_id);
    return (cu?.full_name ?? '').toLowerCase().includes(q)
      || (cu?.phone ?? '').toLowerCase().includes(q)
      || (cu?.email ?? '').toLowerCase().includes(q)
      || e.entitlement_no.toLowerCase().includes(q)
      || e.package_name.toLowerCase().includes(q)
      || invoiceNosFor(e).some(n => n.toLowerCase().includes(q));
  };

  // ---- Qualification wizard (shared modal) ----
  const [wiz, setWiz] = useState(false);
  const openWiz = () => setWiz(true);

  // ---- Rule editor ----
  const [ruleModal, setRuleModal] = useState<TherapyPackageRule | 'new' | null>(null);
  const [rf, setRf] = useState<any>({});
  const openRule = (r?: TherapyPackageRule) => {
    setRf(r ? { ...r } : { store_id: stores[0]?.id ?? '', name: '', qualifying_amount: 0, entitlement_kind: 'unlimited', duration_months: 1, voucher_qty: null, activation_deadline_days: 365, is_active: true });
    setRuleModal(r ?? 'new');
  };
  const saveRule = async () => {
    if (!rf.name?.trim() || !rf.store_id || !rf.qualifying_amount) { alert('Store, name, and qualifying amount are required.'); return; }
    const payload = {
      store_id: rf.store_id, name: rf.name.trim(), qualifying_amount: rf.qualifying_amount,
      entitlement_kind: rf.entitlement_kind, duration_months: rf.entitlement_kind === 'unlimited' ? (rf.duration_months || 1) : null,
      voucher_qty: rf.entitlement_kind === 'voucher' ? (rf.voucher_qty || 1) : null,
      activation_deadline_days: rf.activation_deadline_days || 365, is_active: rf.is_active,
    };
    const res = ruleModal === 'new' ? await supabase.from('therapy_package_rules').insert(payload)
      : await supabase.from('therapy_package_rules').update({ ...payload, updated_at: new Date().toISOString() }).eq('id', (ruleModal as TherapyPackageRule).id);
    if (res.error) { alert(res.error.message); return; }
    setRuleModal(null); load();
  };
  const softDeleteRule = async (r: TherapyPackageRule) => {
    if (!confirm(`Delete rule "${r.name}" at ${sName(r.store_id)}? Existing entitlements keep their snapshot.`)) return;
    await supabase.from('therapy_package_rules').update({ deleted_at: new Date().toISOString(), is_active: false }).eq('id', r.id);
    load();
  };

  const statusBadge = (s: string) => {
    const map: Record<string, string> = { pending_activation: 'badge-muted', scheduled: 'badge-primary', active: 'badge-success', ended: 'badge-muted', expired_before_activation: 'badge-danger', cancelled: 'badge-danger', suspended: 'badge-warning' };
    return <span className={`badge ${map[s] ?? 'badge-muted'}`}>{s.replace(/_/g, ' ')}</span>;
  };

  if (profile?.role === 'inventory_manager') return <NoAccess message="Therapy is not available for your role." />;

  return (
    <div>
      <div className="page-header">
        <div><h2>Therapy</h2><p>Unlimited-therapy qualification and entitlements. Qualify a customer from same-day paid invoices, with an optional top-up.</p></div>
        <div style={{ display: 'flex', gap: 10 }}>
          <button className="btn btn-secondary" onClick={load}><RefreshCw size={15} className={loading ? 'spin' : ''} /> Refresh</button>
          <button className="btn btn-primary" onClick={openWiz}><Sparkles size={16} /> Qualify Customer</button>
        </div>
      </div>

      <div style={{ display: 'flex', gap: 6, marginBottom: 16, borderBottom: '1px solid var(--border)' }}>
        {([['entitlements', 'Entitlements'], ['beneficiaries', 'Beneficiaries'], ['rules', 'Package Rules']] as const).map(([v, l]) => (
          <button key={v} onClick={() => setTab(v)} style={{ padding: '8px 16px', background: 'none', border: 'none', borderBottom: tab === v ? '2px solid var(--primary)' : '2px solid transparent', color: tab === v ? 'var(--primary)' : 'var(--text-secondary)', fontWeight: tab === v ? 700 : 500, cursor: 'pointer' }}>{l}</button>
        ))}
      </div>

      {tab === 'entitlements' && (() => {
        const q = entSearch.trim().toLowerCase();
        const withInfo = ents.map(e => ({ e, info: assignInfo(e) }));
        const counts = {
          all: ents.length,
          unassigned: withInfo.filter(x => x.info.state === 'unassigned').length,
          partial: withInfo.filter(x => x.info.state === 'partial').length,
          complete: withInfo.filter(x => x.info.state === 'complete').length,
        };
        const shown = withInfo.filter(({ e, info }) =>
          (assignFilter === 'all' || info.state === assignFilter) && entMatches(e, q));

        const assignBadge = (state: string, used: number, total: number, unit: string) => {
          if (state === 'unassigned') return <span className="badge badge-warning">Not assigned</span>;
          if (state === 'partial') return <span className="badge badge-primary">Partially assigned</span>;
          return <span className="badge badge-success">Fully assigned</span>;
        };

        return (
          <div>
            <div style={{ display: 'flex', gap: 10, marginBottom: 12, flexWrap: 'wrap', alignItems: 'center' }}>
              <div style={{ position: 'relative', flex: 1, minWidth: 260 }}>
                <Search size={14} style={{ position: 'absolute', left: 10, top: '50%', transform: 'translateY(-50%)', color: 'var(--text-muted)' }} />
                <input value={entSearch} onChange={ev => setEntSearch(ev.target.value)}
                  placeholder="Search customer name, phone, email, entitlement no. or invoice no.…" style={{ paddingLeft: 30 }} />
              </div>
            </div>
            <div style={{ display: 'flex', gap: 6, marginBottom: 14, flexWrap: 'wrap' }}>
              {([['all', 'All'], ['unassigned', 'Not assigned'], ['partial', 'Partially assigned'], ['complete', 'Fully assigned']] as const).map(([v, lbl]) => (
                <button key={v} className={`btn btn-sm ${assignFilter === v ? 'btn-primary' : 'btn-secondary'}`} onClick={() => setAssignFilter(v)}>
                  {lbl} ({counts[v]})
                </button>
              ))}
            </div>

            <div className="card"><div className="table-wrap">
              {loading ? <div className="empty-state"><RefreshCw size={24} className="spin" style={{ opacity: 0.4 }} /></div>
                : shown.length === 0 ? <div className="empty-state"><Sparkles size={32} style={{ opacity: 0.3 }} />
                    <p style={{ fontWeight: 600, marginTop: 8 }}>{ents.length === 0 ? 'No entitlements yet' : 'No entitlements match'}</p>
                    {ents.length > 0 && <p style={{ fontSize: 12.5, color: 'var(--text-muted)' }}>Adjust the filter or search above.</p>}</div>
                : <table>
                    <thead><tr><th>Entitlement</th><th>Customer</th><th>Package</th><th>Store</th><th>Activate by</th><th>Beneficiaries</th><th>Status</th><th></th></tr></thead>
                    <tbody>{shown.map(({ e, info }) => {
                      const invNos = invoiceNosFor(e);
                      return (
                        <tr key={e.id}>
                          <td><strong>{e.entitlement_no}</strong>
                            {invNos.length > 0 && <div style={{ fontSize: 11, color: 'var(--text-muted)' }}>{invNos.join(', ')}</div>}
                            {e.forfeited_value > 0 && <div style={{ fontSize: 11, color: 'var(--text-muted)' }}>Forfeited {money(e.forfeited_value)}</div>}</td>
                          <td>{cName(e.customer_id)}
                            <div style={{ fontSize: 11, color: 'var(--text-muted)' }}>{customers.find(c => c.id === e.customer_id)?.phone}</div></td>
                          <td>{e.package_name}<div style={{ fontSize: 11, color: 'var(--text-muted)' }}>{e.entitlement_kind === 'unlimited' ? `${e.duration_months} mo` : `${e.voucher_qty} vouchers`}</div></td>
                          <td style={{ fontSize: 12.5 }}>{sName(e.store_id)}</td>
                          <td style={{ fontSize: 12.5 }}>{new Date(e.activation_deadline).toLocaleDateString()}</td>
                          <td>
                            {assignBadge(info.state, info.used, info.total, info.unit)}
                            <div style={{ fontSize: 11, color: 'var(--text-muted)', marginTop: 2 }}>{info.used} of {info.total} {info.unit} assigned</div>
                          </td>
                          <td>{statusBadge(e.status)}</td>
                          <td><button className="btn btn-secondary btn-sm" onClick={() => setManageEnt(e)}><Users size={13} /> Manage</button></td>
                        </tr>
                      );
                    })}</tbody>
                  </table>}
            </div></div>
          </div>
        );
      })()}

      {tab === 'beneficiaries' && (() => {
        const ALL: string[] = ['active', 'scheduled', 'pending_activation', 'ended', 'expired_before_activation', 'suspended', 'cancelled'];
        const toggle = (s: string) => setBenFilter(f => f.includes(s) ? f.filter(x => x !== s) : [...f, s]);
        const q = benSearch.trim().toLowerCase();

        const matching = bens.filter(b => {
          if (benFilter.length && !benFilter.includes(b.status)) return false;
          if (!q) return true;
          const cu = customers.find(c => c.id === b.beneficiary_customer_id);
          const beneficiaryHit = !!cu && (
            cu.full_name.toLowerCase().includes(q) ||
            cu.phone.toLowerCase().includes(q) ||
            (cu.email ?? '').toLowerCase().includes(q));
          // Also match on the entitlement / invoice behind this beneficiary.
          const ent = ents.find(x => x.id === b.entitlement_id);
          const entHit = !!ent && (
            ent.entitlement_no.toLowerCase().includes(q) ||
            ent.package_name.toLowerCase().includes(q) ||
            invoiceNosFor(ent).some(n => n.toLowerCase().includes(q)));
          return beneficiaryHit || entHit;
        });

        // Group by beneficiary customer.
        const groups = new Map<string, typeof matching>();
        matching.forEach(b => {
          const arr = groups.get(b.beneficiary_customer_id) ?? [];
          arr.push(b); groups.set(b.beneficiary_customer_id, arr);
        });
        const ordered = [...groups.entries()].sort((a, b) => cName(a[0]).localeCompare(cName(b[0])));

        return (
          <div>
            <div style={{ display: 'flex', gap: 10, marginBottom: 12, flexWrap: 'wrap', alignItems: 'center' }}>
              <div style={{ position: 'relative', flex: 1, minWidth: 220 }}>
                <Search size={14} style={{ position: 'absolute', left: 10, top: '50%', transform: 'translateY(-50%)', color: 'var(--text-muted)' }} />
                <input value={benSearch} onChange={e => setBenSearch(e.target.value)} placeholder="Search beneficiary name, phone, email, entitlement no. or invoice no.…" style={{ paddingLeft: 30 }} />
              </div>
              <button className="btn btn-secondary btn-sm" onClick={() => setBenFilter(benFilter.length === ALL.length ? ['active', 'scheduled'] : ALL)}>
                {benFilter.length === ALL.length ? 'Reset to live + upcoming' : 'Show all statuses'}
              </button>
            </div>
            <div style={{ display: 'flex', gap: 6, marginBottom: 14, flexWrap: 'wrap' }}>
              {ALL.map(s => (
                <button key={s} className={`btn btn-sm ${benFilter.includes(s) ? 'btn-primary' : 'btn-secondary'}`} onClick={() => toggle(s)}>
                  {s.replace(/_/g, ' ')} ({bens.filter(b => b.status === s).length})
                </button>
              ))}
            </div>

            {ordered.length === 0 ? (
              <div className="card"><div className="empty-state"><Users size={32} style={{ opacity: 0.3 }} />
                <p style={{ fontWeight: 600, marginTop: 8 }}>No beneficiaries match</p>
                <p style={{ fontSize: 12.5, color: 'var(--text-muted)' }}>Adjust the status filters or search above.</p></div></div>
            ) : ordered.map(([custId, rows]) => {
              const cu = customers.find(c => c.id === custId);
              const activeCount = rows.filter(r => r.status === 'active').length;
              const upcomingCount = rows.filter(r => r.status === 'scheduled').length;
              const initials = (cu?.full_name ?? '?').trim().split(/\s+/).slice(0, 2).map(w => w[0]).join('').toUpperCase();
              return (
                <div className="card" key={custId} style={{ marginBottom: 14, padding: 0, overflow: 'hidden' }}>
                  {/* Customer header */}
                  <div style={{
                    display: 'flex', alignItems: 'center', gap: 12, padding: '14px 16px',
                    background: 'var(--surface-2)', borderBottom: '1px solid var(--border)', flexWrap: 'wrap',
                  }}>
                    <div style={{
                      width: 40, height: 40, borderRadius: '50%', flexShrink: 0,
                      background: 'var(--primary)', color: '#fff', display: 'flex',
                      alignItems: 'center', justifyContent: 'center', fontWeight: 700, fontSize: 14,
                    }}>{initials}</div>

                    <div style={{ flex: 1, minWidth: 180 }}>
                      <div style={{ fontWeight: 700, fontSize: 15, lineHeight: 1.3 }}>{cu?.full_name ?? '—'}</div>
                      <div style={{ display: 'flex', gap: 14, flexWrap: 'wrap', marginTop: 3 }}>
                        {cu?.phone && (
                          <span style={{ display: 'inline-flex', alignItems: 'center', gap: 4, fontSize: 12, color: 'var(--text-secondary)' }}>
                            <Phone size={11} style={{ opacity: 0.6 }} />{cu.phone}
                          </span>
                        )}
                        {cu?.email && (
                          <span style={{ display: 'inline-flex', alignItems: 'center', gap: 4, fontSize: 12, color: 'var(--text-secondary)' }}>
                            <Mail size={11} style={{ opacity: 0.6 }} />{cu.email}
                          </span>
                        )}
                      </div>
                    </div>

                    <div style={{ display: 'flex', gap: 6, flexWrap: 'wrap', alignItems: 'center' }}>
                      {activeCount > 0 && (
                        <span style={{
                          display: 'inline-flex', alignItems: 'center', gap: 5, padding: '4px 10px',
                          borderRadius: 999, background: 'var(--success-light)', color: 'var(--success)',
                          fontSize: 11.5, fontWeight: 600, whiteSpace: 'nowrap',
                        }}>
                          <span style={{ width: 6, height: 6, borderRadius: '50%', background: 'currentColor' }} />
                          Therapy active{activeCount > 1 ? ` (${activeCount})` : ''}
                        </span>
                      )}
                      {upcomingCount > 0 && (
                        <span style={{
                          display: 'inline-flex', alignItems: 'center', gap: 5, padding: '4px 10px',
                          borderRadius: 999, background: 'var(--surface)', border: '1px solid var(--border)',
                          color: 'var(--text-secondary)', fontSize: 11.5, fontWeight: 600, whiteSpace: 'nowrap',
                        }}>
                          <CalendarClock size={11} />
                          {upcomingCount} upcoming
                        </span>
                      )}
                      <span style={{ fontSize: 11.5, color: 'var(--text-muted)', whiteSpace: 'nowrap' }}>
                        {rows.length} period{rows.length > 1 ? 's' : ''}
                      </span>
                    </div>
                  </div>

                  <div className="table-wrap" style={{ padding: '0 4px 4px' }}>
                    <table>
                      <thead><tr><th>Entitlement</th><th>Package</th><th>Portion</th><th>Activated</th><th>Ends</th><th>Status</th><th></th></tr></thead>
                      <tbody>{rows.map(b => {
                        const ent = ents.find(x => x.id === b.entitlement_id);
                        if (!ent) return null;
                        const unlimited = ent.entitlement_kind === 'unlimited';
                        return (
                          <tr key={b.id}>
                            <td style={{ fontSize: 12.5 }}><strong>{ent.entitlement_no}</strong>
                              {invoiceNosFor(ent).length > 0 && <div style={{ color: 'var(--text-muted)', fontSize: 11 }}>{invoiceNosFor(ent).join(', ')}</div>}
                              <div style={{ color: 'var(--text-muted)', fontSize: 11 }}>{sName(ent.store_id)}</div></td>
                            <td style={{ fontSize: 12.5 }}>{ent.package_name}</td>
                            <td style={{ fontSize: 12.5 }}>{unlimited ? `${b.portion_months} mo` : `${b.portion_vouchers} vouchers`}</td>
                            <td style={{ fontSize: 12.5 }}>{b.activation_date ? new Date(b.activation_date).toLocaleDateString() : '—'}</td>
                            <td style={{ fontSize: 12.5 }}>{unlimited ? (b.ending_date ? new Date(b.ending_date).toLocaleDateString() : '—') : <span style={{ color: 'var(--text-muted)' }}>no expiry</span>}</td>
                            <td>{benBadge(b.status)}</td>
                            <td><TherapyBeneficiaryActions beneficiary={b} entitlement={ent} customers={customers}
                              onChanged={async () => { await supabase.rpc('refresh_therapy_statuses'); await load(); }} /></td>
                          </tr>
                        );
                      })}</tbody>
                    </table>
                  </div>
                </div>
              );
            })}
          </div>
        );
      })()}

      {tab === 'rules' && (
        <div className="card">
          <div style={{ display: 'flex', justifyContent: 'flex-end', marginBottom: 12 }}>
            {canConfig && <button className="btn btn-primary btn-sm" onClick={() => openRule()}><Plus size={14} /> Add Rule</button>}
          </div>
          <div className="table-wrap">
            <table>
              <thead><tr><th>Store</th><th>Package</th><th style={{ textAlign: 'right' }}>Qualifying</th><th>Grants</th><th>Activate within</th><th>Status</th>{canConfig && <th></th>}</tr></thead>
              <tbody>{rules.map(r => (
                <tr key={r.id}>
                  <td style={{ fontSize: 12.5 }}>{sName(r.store_id)}</td>
                  <td><strong>{r.name}</strong></td>
                  <td style={{ textAlign: 'right' }}>{money(r.qualifying_amount)}</td>
                  <td>{r.entitlement_kind === 'unlimited' ? `${r.duration_months} month(s) unlimited` : `${r.voucher_qty} vouchers`}</td>
                  <td style={{ fontSize: 12.5 }}>{r.activation_deadline_days} days</td>
                  <td>{r.is_active ? <span className="badge badge-success">Active</span> : <span className="badge badge-muted">Inactive</span>}</td>
                  {canConfig && <td><div style={{ display: 'flex', gap: 4 }}><button className="btn btn-secondary btn-sm btn-icon" onClick={() => openRule(r)}><Pencil size={13} /></button><button className="btn btn-danger btn-sm btn-icon" onClick={() => softDeleteRule(r)}><Trash2 size={13} /></button></div></td>}
                </tr>
              ))}</tbody>
            </table>
          </div>
        </div>
      )}

      {/* Qualification wizard (shared) */}
      {wiz && (
        <TherapyQualifyModal
          stores={stores} customers={customers} rules={rules}
          onClose={() => setWiz(false)}
          onCreated={(res) => { setWiz(false); load(); alert(`Created ${res?.entitlement_ids?.length ?? 0} entitlement(s). Forfeited ${money(res?.forfeited ?? 0)}.`); }}
        />
      )}

      {manageEnt && (
        <TherapyEntitlementModal
          entitlement={manageEnt} beneficiaries={bens} dateRequests={dateReqs} customers={customers}
          onClose={() => setManageEnt(null)}
          onChanged={async () => { await supabase.rpc('refresh_therapy_statuses'); await load(); }}
        />
      )}

      {/* Rule editor */}
      {ruleModal && (
        <Modal title={ruleModal === 'new' ? 'Add Package Rule' : 'Edit Package Rule'} maxWidth={460} onClose={() => setRuleModal(null)}
          footer={<><button className="btn btn-secondary" onClick={() => setRuleModal(null)}>Cancel</button><button className="btn btn-primary" onClick={saveRule}>Save</button></>}>
          <div className="form-grid">
            <div className="form-group"><label>Store *</label><select value={rf.store_id} onChange={e => setRf((f: any) => ({ ...f, store_id: e.target.value }))}>{stores.map(s => <option key={s.id} value={s.id}>{s.name}</option>)}</select></div>
            <div className="form-group"><label>Package name *</label><input value={rf.name} onChange={e => setRf((f: any) => ({ ...f, name: e.target.value }))} /></div>
            <div className="form-grid-2">
              <div className="form-group"><label>Qualifying amount *</label><input type="number" min={0} step="0.01" value={rf.qualifying_amount || ''} onChange={e => setRf((f: any) => ({ ...f, qualifying_amount: +e.target.value }))} /></div>
              <div className="form-group"><label>Type</label><select value={rf.entitlement_kind} onChange={e => setRf((f: any) => ({ ...f, entitlement_kind: e.target.value }))}><option value="unlimited">Unlimited (months)</option><option value="voucher">Vouchers</option></select></div>
            </div>
            <div className="form-grid-2">
              {rf.entitlement_kind === 'unlimited'
                ? <div className="form-group"><label>Duration (months)</label><input type="number" min={1} value={rf.duration_months || ''} onChange={e => setRf((f: any) => ({ ...f, duration_months: +e.target.value }))} /></div>
                : <div className="form-group"><label>Voucher quantity</label><input type="number" min={1} value={rf.voucher_qty || ''} onChange={e => setRf((f: any) => ({ ...f, voucher_qty: +e.target.value }))} /></div>}
              <div className="form-group"><label>Activation deadline (days)</label><input type="number" min={1} value={rf.activation_deadline_days || ''} onChange={e => setRf((f: any) => ({ ...f, activation_deadline_days: +e.target.value }))} /></div>
            </div>
            <label style={{ display: 'flex', alignItems: 'center', gap: 8, cursor: 'pointer' }}><input type="checkbox" checked={rf.is_active} onChange={e => setRf((f: any) => ({ ...f, is_active: e.target.checked }))} style={{ width: 'auto' }} /><span style={{ fontSize: 13 }}>Active</span></label>
            <div className="alert alert-info" style={{ marginBottom: 0 }}><span>ℹ️</span><div>Rule changes affect future qualifications only. Existing entitlements keep the rule they were created with.</div></div>
          </div>
        </Modal>
      )}
    </div>
  );
};

export default TherapyPage;
