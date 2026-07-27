import React, { useEffect, useState, useCallback, useMemo } from 'react';
import { supabase } from '../lib/supabase';
import { useAuth } from '../context/AuthContext';
import { Store, Customer, UnlimitedTherapyPackage, UnlimitedTherapyStorePrice, PurchasedTherapyEntitlement, isOwnerOrManager } from '../types';
import { Modal, DateModal, ReasonModal } from '../components/ui';
import { RefreshCw, Plus, Sparkles, Search, CalendarClock, Play, Ban, Archive, Pencil } from 'lucide-react';
import StorePriceEditor from '../components/StorePriceEditor';

const money = (n: number) => `S$${Number(n ?? 0).toFixed(2)}`;
const d = (s?: string | null) => s ? new Date(s).toLocaleDateString('en-GB') : '—';
const sgToday = () => new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Singapore' });

const PSTATUS: Record<string, { cls: string; label: string }> = {
  pending_activation: { cls: 'badge-accent', label: 'Pending Activation' },
  scheduled: { cls: 'badge-primary', label: 'Scheduled' },
  active: { cls: 'badge-success', label: 'Active' },
  expired: { cls: 'badge-muted', label: 'Expired' },
  cancelled: { cls: 'badge-danger', label: 'Cancelled' },
  refunded: { cls: 'badge-danger', label: 'Refunded' },
};

const TherapyPage: React.FC = () => {
  const { profile } = useAuth();
  const canManage = isOwnerOrManager(profile?.role);
  const [tab, setTab] = useState<'purchased' | 'legacy' | 'packages' | 'qualification'>('purchased');
  const [loading, setLoading] = useState(true);
  const [err, setErr] = useState<string | null>(null);

  const [ents, setEnts] = useState<PurchasedTherapyEntitlement[]>([]);
  const [legacy, setLegacy] = useState<any[]>([]);
  const [packages, setPackages] = useState<UnlimitedTherapyPackage[]>([]);
  const [stores, setStores] = useState<Store[]>([]);
  const [customers, setCustomers] = useState<Customer[]>([]);
  const [search, setSearch] = useState('');
  const [busy, setBusy] = useState<string | null>(null);

  // activation modal
  const [actEnt, setActEnt] = useState<PurchasedTherapyEntitlement | null>(null);
  const [actDate, setActDate] = useState('');
  const [actReason, setActReason] = useState('');
  // package modal
  const [pkgModal, setPkgModal] = useState<UnlimitedTherapyPackage | null | 'new'>(null);
  const [pkgName, setPkgName] = useState(''); const [pkgMonths, setPkgMonths] = useState(12);
  const [pkgDesc, setPkgDesc] = useState(''); const [pkgActive, setPkgActive] = useState(true);
  const [priceFor, setPriceFor] = useState<{ id: string; name: string } | null>(null);
  const [reschedEnt, setReschedEnt] = useState<PurchasedTherapyEntitlement | null>(null);
  const [reschedDate, setReschedDate] = useState<string | null>(null);   // step 1 result -> step 2 asks reason
  const [refundEnt, setRefundEnt] = useState<PurchasedTherapyEntitlement | null>(null);

  // Same-day qualification rules (Phase 22).
  const [rules, setRules] = useState<any[]>([]);
  const [backfillBusy, setBackfillBusy] = useState(false);
  const [backfillRes, setBackfillRes] = useState<any>(null);
  const [setupStatus, setSetupStatus] = useState<any>(null);
  const [affDay, setAffDay] = useState<string>('');
  const [affRows, setAffRows] = useState<any[]>([]);
  const loadAffiliateDay = async (day?: string) => {
    const target = day ?? affDay ?? '';
    const { data } = await supabase.rpc('affiliate_legacy_day_summary', { p_day: target || null });
    setAffRows((data as any[]) ?? []);
  };
  const runBackfill = async () => {
    if (!confirm('Re-check every paid day against the current qualification rules? Entitlements already claimed are never changed.')) return;
    setBackfillBusy(true); setErr(null);
    const { data, error } = await supabase.rpc('backfill_legacy_qualification',
      { p_from: null, p_to: null, p_store_id: null });
    setBackfillBusy(false);
    if (error) { setErr(error.message); return; }
    setBackfillRes(data); load();
  };
  const emptyRule = { id: null as string | null, store_id: '', name: '', qualifying_amount: '', entitlement_kind: 'unlimited', duration_months: '', voucher_qty: '', activation_deadline_days: '365', is_active: true, effective_date: '', applies_to: 'customer' };
  const [ruleForm, setRuleForm] = useState<typeof emptyRule | null>(null);
  const [ruleBusy, setRuleBusy] = useState(false);
  const [ruleErr, setRuleErr] = useState<string | null>(null);
  const saveRule = async () => {
    if (!ruleForm) return;
    setRuleBusy(true); setRuleErr(null);
    const { error } = await supabase.rpc('upsert_legacy_rule', {
      p_id: ruleForm.id, p_store_id: ruleForm.store_id || null, p_name: ruleForm.name,
      p_qualifying_amount: ruleForm.qualifying_amount === '' ? null : Number(ruleForm.qualifying_amount),
      p_entitlement_kind: ruleForm.entitlement_kind,
      p_duration_months: ruleForm.duration_months === '' ? null : Number(ruleForm.duration_months),
      p_voucher_qty: ruleForm.voucher_qty === '' ? null : Number(ruleForm.voucher_qty),
      p_activation_deadline_days: ruleForm.activation_deadline_days === '' ? 365 : Number(ruleForm.activation_deadline_days),
      p_is_active: ruleForm.is_active,
      p_effective_date: ruleForm.effective_date || null,
      p_applies_to: ruleForm.applies_to,
    });
    setRuleBusy(false);
    if (error) { setRuleErr(error.message); return; }
    setRuleForm(null); load();
  };

  const load = useCallback(async () => {
    setLoading(true); setErr(null);
    const [pe, le, pk, st, cu, ru] = await Promise.all([
      supabase.from('purchased_therapy_entitlements').select('*').order('created_at', { ascending: false }),
      supabase.from('therapy_entitlements').select('*').order('created_at', { ascending: false }),
      supabase.from('unlimited_therapy_packages').select('*').is('deleted_at', null).order('duration_months'),
      supabase.from('stores').select('*').is('deleted_at', null).eq('is_active', true).order('name'),
      supabase.from('customers').select('id, full_name, phone').is('deleted_at', null),
      supabase.from('therapy_package_rules').select('*').is('deleted_at', null).order('created_at', { ascending: false }),
    ]);
    if (pe.error && !/relation.*does not exist/.test(pe.error.message)) setErr(pe.error.message);
    setEnts((pe.data as PurchasedTherapyEntitlement[]) ?? []);
    setLegacy((le.data as any[]) ?? []);
    setPackages((pk.data as UnlimitedTherapyPackage[]) ?? []);
    setStores((st.data as Store[]) ?? []);
    setCustomers((cu.data as Customer[]) ?? []);
    setRules((ru.data as any[]) ?? []);
    const { data: st2 } = await supabase.rpc('legacy_setup_status');
    setSetupStatus(st2 ?? null);
    setLoading(false);
  }, []);
  useEffect(() => { load(); }, [load]);

  const cName = (id: string) => customers.find(c => c.id === id)?.full_name ?? '—';
  const cPhone = (id: string) => customers.find(c => c.id === id)?.phone ?? '';

  const openActivate = (e: PurchasedTherapyEntitlement) => { setActEnt(e); setActDate(sgToday()); setActReason(''); setErr(null); };
  const doActivate = async (future: boolean) => {
    if (!actEnt) return;
    setBusy(actEnt.id); setErr(null);
    const { error } = await supabase.rpc('activate_purchased_therapy', {
      p_entitlement_id: actEnt.id,
      p_activation_date: future ? actDate : null,
      p_reason: actReason || null,
    });
    setBusy(null);
    if (error) { setErr(error.message); return; }
    setActEnt(null); load();
  };
  const doReschedule = (e: PurchasedTherapyEntitlement) => { setReschedEnt(e); setReschedDate(null); };
  const submitReschedule = async (e: PurchasedTherapyEntitlement, newDate: string, reason: string) => {
    setBusy(e.id);
    const { error } = await supabase.rpc('reschedule_purchased_therapy', { p_entitlement_id: e.id, p_new_date: newDate, p_reason: reason });
    setBusy(null);
    setReschedEnt(null); setReschedDate(null);
    if (error) { setErr(error.message); return; }
    load();
  };
  const doRefund = (e: PurchasedTherapyEntitlement) => setRefundEnt(e);
  const submitRefund = async (e: PurchasedTherapyEntitlement, reason: string) => {
    setBusy(e.id);
    const { error } = await supabase.rpc('refund_purchased_therapy', { p_entitlement_id: e.id, p_reason: reason });
    setBusy(null);
    setRefundEnt(null);
    if (error) { setErr(error.message); return; }
    load();
  };
  // Claiming a Legacy entitlement: pick the start date, then it runs for its
  // duration (or is simply claimed, for a voucher reward).
  const [claimEnt, setClaimEnt] = useState<any | null>(null);
  const [claimDate, setClaimDate] = useState<string>('');
  const [claimBusy, setClaimBusy] = useState(false);
  const [claimErr, setClaimErr] = useState<string | null>(null);
  const [claimDone, setClaimDone] = useState<any | null>(null);
  const [rewardOptions, setRewardOptions] = useState<any[]>([]);
  const [chosenRule, setChosenRule] = useState<string>('');
  const [voucherOptions, setVoucherOptions] = useState<any[]>([]);
  const [basket, setBasket] = useState<Record<string, number>>({});

  const openClaim = async (e: any) => {
    setClaimEnt(e); setClaimDate(sgToday()); setClaimErr(null); setClaimDone(null);
    setBasket({}); setChosenRule('');
    const { data: opts } = await supabase.rpc('legacy_reward_options', { p_entitlement_id: e.id });
    const list = (opts as any[]) ?? [];
    setRewardOptions(list);
    // Default to the reward the entitlement already carries.
    const match = list.find(o => o.entitlement_kind === e.entitlement_kind && o.name === e.package_name);
    setChosenRule(match ? match.rule_id : (list.length === 1 ? list[0].rule_id : ''));
    const { data: vo } = await supabase.rpc('legacy_reward_voucher_options', { p_store_id: e.store_id });
    setVoucherOptions((vo as any[]) ?? []);
  };
  const submitClaim = async () => {
    if (!claimEnt) return;
    setClaimBusy(true); setClaimErr(null);
    const sel = Object.entries(basket).filter(([, q]) => q > 0)
      .map(([voucher_id, quantity]) => ({ voucher_id, quantity }));
    const { data, error } = await supabase.rpc('claim_legacy_therapy', {
      p_entitlement_id: claimEnt.id, p_activation_date: claimDate || null,
      p_rule_id: chosenRule || null,
      p_voucher_selections: sel.length ? sel : null,
    });
    setClaimBusy(false);
    if (error) { setClaimErr(error.message); return; }
    setClaimDone(data); setClaimEnt(null); load();
  };

  const openPkg = (p: UnlimitedTherapyPackage | 'new') => {
    setPkgModal(p);
    if (p === 'new') { setPkgName(''); setPkgMonths(12); setPkgDesc(''); setPkgActive(true); }
    else { setPkgName(p.name); setPkgMonths(p.duration_months); setPkgDesc(p.description ?? ''); setPkgActive(p.is_active); }
  };
  const savePkg = async () => {
    setBusy('pkg');
    const { error } = await supabase.rpc('upsert_unlimited_therapy_package', {
      p_id: pkgModal === 'new' ? null : (pkgModal as UnlimitedTherapyPackage).id,
      p_name: pkgName, p_duration_months: pkgMonths, p_description: pkgDesc || null, p_is_active: pkgActive,
    });
    setBusy(null);
    if (error) { setErr(error.message); return; }
    setPkgModal(null); load();
  };

  const filteredEnts = useMemo(() => {
    const s = search.trim().toLowerCase();
    if (!s) return ents;
    return ents.filter(e => cName(e.customer_id).toLowerCase().includes(s) || cPhone(e.customer_id).includes(s) || e.entitlement_no.toLowerCase().includes(s) || e.package_name.toLowerCase().includes(s));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [ents, search, customers]);

  return (
    <div>
      <div className="page-header">
        <div><h2>Therapy</h2><p>Unlimited Therapy packages are purchased on an invoice. Target-based qualification has been retired; historical entitlements are read-only.</p></div>
        <button className="btn btn-secondary" onClick={load}><RefreshCw size={16} /> Refresh</button>
      </div>
      {err && <div className="alert alert-danger"><span>⚠</span><div>{err}</div></div>}

      <div style={{ display: 'flex', gap: 4, borderBottom: '1px solid var(--border)', marginBottom: 16 }}>
        {([['purchased', 'Purchased'], ['legacy', 'Legacy Therapy'], ...(canManage ? [['qualification', 'Qualification'], ['packages', 'Packages']] : [])] as [typeof tab, string][]).map(([v, l]) => (
          <button key={v} onClick={() => setTab(v)}
            style={{ padding: '8px 16px', background: 'none', border: 'none', display: 'inline-flex', alignItems: 'center', gap: 6,
              borderBottom: tab === v ? '2px solid var(--primary)' : '2px solid transparent',
              color: tab === v ? 'var(--primary)' : 'var(--text-secondary)', fontWeight: tab === v ? 700 : 500, cursor: 'pointer', marginBottom: -1 }}>
            {v === 'legacy' && <Archive size={13} />}{l}
          </button>
        ))}
      </div>

      {tab === 'purchased' && (
        <>
          <div style={{ position: 'relative', marginBottom: 12, maxWidth: 380 }}>
            <Search size={15} style={{ position: 'absolute', left: 10, top: 10, opacity: 0.4 }} />
            <input value={search} onChange={e => setSearch(e.target.value)} placeholder="Search customer, phone, no. or package…" style={{ paddingLeft: 32 }} />
          </div>
          <div className="card">
            {loading ? <div style={{ textAlign: 'center', padding: 40 }}><RefreshCw size={20} className="spin" style={{ opacity: 0.4 }} /></div>
            : filteredEnts.length === 0 ? <div className="empty-state" style={{ padding: 40 }}><Sparkles size={30} style={{ opacity: 0.3 }} /><p style={{ marginTop: 10 }}>No purchased therapy yet. Sell an Unlimited Therapy package on an invoice.</p></div>
            : (
              <div className="table-wrap">
                <table>
                  <thead><tr><th>No.</th><th>Customer</th><th>Package</th><th>Purchased</th><th>Deadline</th><th>Activation</th><th>Expiry</th><th>Status</th><th></th></tr></thead>
                  <tbody>
                    {filteredEnts.map(e => {
                      const stt = PSTATUS[e.status] ?? { cls: 'badge-muted', label: e.status };
                      const canAct = e.status === 'pending_activation' || e.status === 'scheduled';
                      return (
                        <tr key={e.id}>
                          <td style={{ fontWeight: 600 }}>{e.entitlement_no}</td>
                          <td><div>{cName(e.customer_id)}</div><div style={{ fontSize: 11, color: 'var(--text-muted)' }}>{cPhone(e.customer_id)}</div></td>
                          <td>{e.package_name}<div style={{ fontSize: 11, color: 'var(--text-muted)' }}>{e.duration_months} mo · {money(e.price_snapshot)}</div></td>
                          <td style={{ fontSize: 12 }}>{d(e.purchase_date)}</td>
                          <td style={{ fontSize: 12 }}>{d(e.activation_deadline)}</td>
                          <td style={{ fontSize: 12 }}>{d(e.activation_date ?? e.scheduled_date)}</td>
                          <td style={{ fontSize: 12 }}>{d(e.expiry_date)}</td>
                          <td><span className={`badge ${stt.cls}`}>{stt.label}</span></td>
                          <td>
                            <div style={{ display: 'flex', gap: 4, flexWrap: 'wrap' }}>
                              {canAct && <button className="btn btn-primary btn-sm" disabled={busy === e.id} onClick={() => openActivate(e)}><Play size={12} /> Activate</button>}
                              {canAct && <button className="btn btn-secondary btn-sm" disabled={busy === e.id} onClick={() => doReschedule(e)}><CalendarClock size={12} /></button>}
                              {canManage && canAct && <button className="btn btn-danger btn-sm" disabled={busy === e.id} onClick={() => doRefund(e)}><Ban size={12} /> Refund</button>}
                            </div>
                          </td>
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
              </div>
            )}
          </div>
        </>
      )}

      {tab === 'legacy' && (
        <div className="card">
          <div style={{ padding: '10px 12px', borderBottom: '1px solid var(--border)', fontSize: 12.5, color: 'var(--text-muted)' }}>
            Legacy therapy entitlements. Same-day qualification earns these automatically when a customer's paid invoices at a store reach the qualifying amount on one Singapore day. Pending entitlements can be activated within their deadline. Set the threshold and reward under the Qualification tab.
          </div>
          {loading ? <div style={{ textAlign: 'center', padding: 40 }}><RefreshCw size={20} className="spin" style={{ opacity: 0.4 }} /></div>
          : legacy.length === 0 ? <div className="empty-state" style={{ padding: 40 }}><Archive size={30} style={{ opacity: 0.3 }} /><p style={{ marginTop: 10 }}>No legacy therapy entitlements.</p></div>
          : (
            <div className="table-wrap">
              <table>
                <thead><tr><th>No.</th><th>Customer</th><th>Package</th><th>Qualified</th><th>Claim by</th><th>Runs</th><th>Status</th><th></th></tr></thead>
                <tbody>
                  {legacy.map(e => {
                    const canActivate = e.status === 'pending_activation' && sgToday() <= e.activation_deadline;
                    const expired = e.status === 'pending_activation' && sgToday() > e.activation_deadline;
                    return (
                      <tr key={e.id}>
                        <td style={{ fontWeight: 600 }}>{e.entitlement_no}</td>
                        <td>{cName(e.customer_id)}{e.earner_kind === 'affiliate' && <div><span className="badge badge-accent" style={{ fontSize: 10 }}>Affiliate</span></div>}</td>
                        <td>{e.package_name}<div style={{ fontSize: 11, color: 'var(--text-muted)' }}>{e.entitlement_kind}{e.duration_months ? ` · ${e.duration_months} mo` : ''}</div></td>
                        <td style={{ fontSize: 12 }}>{money(e.qualified_value)}</td>
                        <td style={{ fontSize: 12 }}>{d(e.activation_deadline)}{expired && <span style={{ color: 'var(--danger)', fontSize: 11 }}> · passed</span>}</td>
                        <td style={{ fontSize: 12 }}>{e.activation_date ? `${d(e.activation_date)} → ${e.expiry_date ? d(e.expiry_date) : '—'}` : '—'}</td>
                        <td><span className={`badge ${e.status === 'active' ? 'badge-success' : e.status === 'pending_activation' ? 'badge-accent' : 'badge-muted'}`}>{String(e.status).replace('_',' ')}</span></td>
                        <td>{canActivate
                          ? <button className="btn btn-primary btn-sm" onClick={() => openClaim(e)}><Play size={12} /> Claim</button>
                          : e.status === 'pending_activation' ? <span style={{ fontSize: 11, color: 'var(--danger)' }}>deadline passed</span>
                          : null}</td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          )}
        </div>
      )}

      {tab === 'packages' && canManage && (
        <>
          <div style={{ marginBottom: 12 }}><button className="btn btn-primary" onClick={() => openPkg('new')}><Plus size={16} /> New Package</button></div>
          <div className="card">
            {packages.length === 0 ? <div className="empty-state" style={{ padding: 40 }}><p>No packages yet.</p></div> : (
              <table>
                <thead><tr><th>Name</th><th>Duration</th><th>Description</th><th>Active</th><th></th></tr></thead>
                <tbody>
                  {packages.map(p => (
                    <tr key={p.id}>
                      <td style={{ fontWeight: 600 }}>{p.name}</td>
                      <td>{p.duration_months} months</td>
                      <td style={{ fontSize: 12, color: 'var(--text-muted)' }}>{p.description ?? '—'}</td>
                      <td>{p.is_active ? <span className="badge badge-success">Active</span> : <span className="badge badge-muted">Inactive</span>}</td>
                      <td>
                        <div style={{ display: 'flex', gap: 4 }}>
                          <button className="btn btn-secondary btn-sm" onClick={() => setPriceFor({ id: p.id, name: p.name })}>Store Prices</button>
                          <button className="btn btn-secondary btn-sm btn-icon" onClick={() => openPkg(p)}><Pencil size={13} /></button>
                        </div>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )}
          </div>
        </>
      )}

      {backfillRes && (
        <Modal title="Qualification re-checked" maxWidth={400} onClose={() => setBackfillRes(null)}
          footer={<button className="btn btn-primary" onClick={() => setBackfillRes(null)}>Done</button>}>
          <div style={{ fontSize: 13 }}>
            <div>{backfillRes.days_evaluated} paid day(s) evaluated{backfillRes.snapshots_filled ? `, ${backfillRes.snapshots_filled} affiliate snapshot(s) filled in` : ''}.</div>
            {(backfillRes.customer_created != null) && <div style={{ marginTop: 4, fontSize: 12, color: 'var(--text-muted)' }}>Customer units: {backfillRes.customer_created} · Affiliate units: {backfillRes.affiliate_created}</div>}
            <div style={{ marginTop: 6 }}><strong>{backfillRes.created}</strong> new entitlement(s) created{Number(backfillRes.cancelled) > 0 ? `, ${backfillRes.cancelled} withdrawn` : ''}.</div>
            {Number(backfillRes.created) === 0 && (
              <div style={{ marginTop: 8, color: 'var(--text-muted)', fontSize: 12 }}>
                Nothing new. If you expected an entitlement, check that a rule exists for that store and that its "Effective from" date is on or before the day the invoice was paid.
              </div>
            )}
          </div>
        </Modal>
      )}

      {claimEnt && (
        <Modal title={`Claim — ${claimEnt.entitlement_no}`} maxWidth={430} onClose={() => setClaimEnt(null)}
          footer={<><button className="btn btn-secondary" onClick={() => setClaimEnt(null)}>Cancel</button>
            <button className="btn btn-primary" onClick={submitClaim} disabled={claimBusy}>{claimBusy ? 'Claiming…' : 'Claim'}</button></>}>
          {(() => {
            const opt = rewardOptions.find(o => o.rule_id === chosenRule);
            const kind = opt ? opt.entitlement_kind : claimEnt.entitlement_kind;
            const qty = opt ? (opt.voucher_qty ?? 0) : (claimEnt.voucher_qty ?? 0);
            const chosenTotal = Object.values(basket).reduce((a, b) => a + (b || 0), 0);
            return (
              <div className="form-grid">
                <div style={{ fontSize: 12.5, color: 'var(--text-secondary)' }}>
                  {cName(claimEnt.customer_id)} · qualified {money(claimEnt.qualified_value)}
                  {claimEnt.earner_kind === 'affiliate' && <span className="badge badge-accent" style={{ marginLeft: 6 }}>Affiliate reward</span>}
                </div>

                {rewardOptions.length > 1 && (
                  <div className="form-group" style={{ marginBottom: 0 }}>
                    <label>Choose the reward</label>
                    {rewardOptions.map(o => (
                      <label key={o.rule_id} style={{ display: 'flex', gap: 7, alignItems: 'flex-start', fontSize: 13, padding: '4px 0', cursor: 'pointer' }}>
                        <input type="radio" name="rewardopt" style={{ width: 'auto', marginTop: 3 }}
                          checked={chosenRule === o.rule_id}
                          onChange={() => { setChosenRule(o.rule_id); setBasket({}); }} />
                        <span>
                          <strong>{o.name}</strong>
                          <div style={{ fontSize: 11.5, color: 'var(--text-muted)' }}>
                            {o.entitlement_kind === 'voucher'
                              ? `${o.voucher_qty ?? 0} voucher(s) — you pick which`
                              : `Unlimited therapy${o.duration_months ? ` for ${o.duration_months} month(s)` : ''}`}
                          </div>
                        </span>
                      </label>
                    ))}
                  </div>
                )}

                {kind === 'voucher' ? (
                  <div className="form-group" style={{ marginBottom: 0 }}>
                    <label>Pick {qty} voucher(s) — {chosenTotal}/{qty} chosen</label>
                    <div style={{ maxHeight: 210, overflowY: 'auto', border: '1px solid var(--border)', borderRadius: 'var(--radius-sm)' }}>
                      {voucherOptions.length === 0 && <div style={{ padding: 10, fontSize: 12, color: 'var(--text-muted)' }}>No reward-eligible vouchers at this store.</div>}
                      {voucherOptions.map(v => {
                        const cur = basket[v.voucher_id] ?? 0;
                        const cap = v.available_qty == null ? qty : Math.min(qty, v.available_qty);
                        return (
                          <div key={v.voucher_id} style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 8, padding: '6px 9px', borderBottom: '1px solid var(--border)' }}>
                            <div style={{ fontSize: 12.5 }}>
                              {v.name}
                              <div style={{ fontSize: 11, color: 'var(--text-muted)' }}>
                                {v.available_qty == null ? 'unlimited' : `${v.available_qty} in stock`}
                              </div>
                            </div>
                            <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
                              <button className="btn btn-secondary btn-sm" disabled={cur <= 0}
                                onClick={() => setBasket(b => ({ ...b, [v.voucher_id]: Math.max(0, (b[v.voucher_id] ?? 0) - 1) }))}>−</button>
                              <span style={{ minWidth: 18, textAlign: 'center', fontSize: 13 }}>{cur}</span>
                              <button className="btn btn-secondary btn-sm"
                                disabled={chosenTotal >= qty || cur >= cap}
                                onClick={() => setBasket(b => ({ ...b, [v.voucher_id]: (b[v.voucher_id] ?? 0) + 1 }))}>+</button>
                            </div>
                          </div>
                        );
                      })}
                    </div>
                    <div style={{ fontSize: 11, color: 'var(--text-muted)', marginTop: 4 }}>
                      You can mix voucher types. These are issued to {cName(claimEnt.customer_id)}, reduce store stock, and never expire.
                    </div>
                  </div>
                ) : (
                  <div className="form-group" style={{ marginBottom: 0 }}>
                    <label>Start date</label>
                    <input type="date" value={claimDate} min={sgToday()} max={claimEnt.activation_deadline ?? undefined}
                      onChange={e => setClaimDate(e.target.value)} />
                    <div style={{ fontSize: 11, color: 'var(--text-muted)', marginTop: 3 }}>
                      A future start date schedules it; today starts it immediately.
                    </div>
                  </div>
                )}

                <div className="alert alert-info" style={{ marginBottom: 0 }}><span>ℹ️</span>
                  <div>Must be claimed on or before {d(claimEnt.activation_deadline)}.</div>
                </div>
                {claimErr && <div className="alert alert-danger" style={{ marginBottom: 0 }}><span>⚠</span><div>{claimErr}</div></div>}
              </div>
            );
          })()}
        </Modal>
      )}

      {claimDone && (
        <Modal title="Claimed" maxWidth={400} onClose={() => setClaimDone(null)}
          footer={<button className="btn btn-primary" onClick={() => setClaimDone(null)}>Done</button>}>
          <div style={{ fontSize: 13 }}>
            <div><strong>{claimDone.entitlement_no}</strong> is now {String(claimDone.status).replace('_',' ')}.</div>
            {claimDone.activation_date && <div style={{ marginTop: 6 }}>Starts {d(claimDone.activation_date)}{claimDone.expiry_date ? ` and runs until ${d(claimDone.expiry_date)}` : ''}.</div>}
            {claimDone.voucher_qty && <div style={{ marginTop: 6 }}>Issue {claimDone.voucher_qty} voucher(s) to the customer.</div>}
          </div>
        </Modal>
      )}

      {tab === 'qualification' && canManage && (
        <>
          {setupStatus && Array.isArray(setupStatus.warnings) && setupStatus.warnings.length > 0 && (
            <div className="alert alert-warning" style={{ marginBottom: 12 }}>
              <span>⚠</span>
              <div>
                <div style={{ fontWeight: 700, marginBottom: 3 }}>Qualification is not fully configured</div>
                {setupStatus.warnings.map((w: string, i: number) => <div key={i} style={{ fontSize: 12.5 }}>{w}</div>)}
              </div>
            </div>
          )}
          <div style={{ marginBottom: 12, display: 'flex', justifyContent: 'space-between', alignItems: 'center', flexWrap: 'wrap', gap: 8 }}>
            <div style={{ fontSize: 12.5, color: 'var(--text-muted)', maxWidth: 620 }}>
              Same-day qualification: when a customer's paid invoices at a store total the qualifying amount on one Singapore day, they earn one Legacy entitlement per whole multiple. With several tiers, the day's total uses the <strong>best tier it reaches</strong>. The remainder carries between invoices on the same day but not to the next day.
            </div>
            <div style={{ display: 'flex', gap: 8 }}>
              <button className="btn btn-secondary" onClick={runBackfill} disabled={backfillBusy}>
                <RefreshCw size={15} className={backfillBusy ? 'spin' : ''} /> {backfillBusy ? 'Checking…' : 'Re-check paid days'}
              </button>
              <button className="btn btn-primary" onClick={() => { setRuleForm({ ...emptyRule }); setRuleErr(null); }}><Plus size={16} /> New Rule</button>
            </div>
          </div>
          <div className="card">
            {rules.length === 0 ? <div className="empty-state" style={{ padding: 40 }}><p>No qualification rules yet. Add one to enable same-day Legacy qualification.</p></div> : (
              <div className="table-wrap">
                <table>
                  <thead><tr><th>Name</th><th>Rewards</th><th>Store</th><th style={{ textAlign: 'right' }}>Qualifying</th><th>Reward</th><th>Effective from</th><th style={{ textAlign: 'right' }}>Claim window</th><th>Active</th><th></th></tr></thead>
                  <tbody>
                    {rules.map(r => (
                      <tr key={r.id}>
                        <td style={{ fontWeight: 600 }}>{r.name}</td>
                        <td><span className={`badge ${r.applies_to === 'affiliate' ? 'badge-accent' : 'badge-muted'}`}>{r.applies_to === 'affiliate' ? 'Affiliate' : 'Customer'}</span></td>
                        <td style={{ fontSize: 12 }}>{r.store_id ? (stores.find(s => s.id === r.store_id)?.name ?? '—') : 'All stores'}</td>
                        <td style={{ textAlign: 'right' }}>{money(r.qualifying_amount)}</td>
                        <td style={{ fontSize: 12 }}>{r.entitlement_kind === 'voucher' ? `${r.voucher_qty ?? 0} voucher(s)` : `Unlimited${r.duration_months ? ` · ${r.duration_months} mo` : ''}`}</td>
                        <td style={{ fontSize: 12 }}>{d(r.effective_date)}</td>
                        <td style={{ textAlign: 'right', fontSize: 12 }}>{r.activation_deadline_days} days</td>
                        <td>{r.is_active ? <span className="badge badge-success">Active</span> : <span className="badge badge-muted">Inactive</span>}</td>
                        <td><button className="btn btn-secondary btn-sm btn-icon" onClick={() => setRuleForm({
                          id: r.id, store_id: r.store_id ?? '', name: r.name ?? '', qualifying_amount: String(r.qualifying_amount ?? ''),
                          entitlement_kind: r.entitlement_kind ?? 'unlimited', duration_months: r.duration_months != null ? String(r.duration_months) : '',
                          voucher_qty: r.voucher_qty != null ? String(r.voucher_qty) : '', activation_deadline_days: String(r.activation_deadline_days ?? 365), is_active: r.is_active,
                          effective_date: r.effective_date ?? '',
                          applies_to: r.applies_to ?? 'customer',
                        })}><Pencil size={13} /></button></td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </div>
        </>
      )}

      {tab === 'qualification' && canManage && (
        <div className="card" style={{ marginTop: 14 }}>
          <div style={{ padding: '10px 12px', borderBottom: '1px solid var(--border)', display: 'flex', justifyContent: 'space-between', alignItems: 'center', flexWrap: 'wrap', gap: 8 }}>
            <div>
              <div style={{ fontWeight: 700, fontSize: 13 }}>Affiliate residual by day</div>
              <div style={{ fontSize: 11.5, color: 'var(--text-muted)' }}>
                What each Affiliate's direct customers left over after taking their own units — and why a reward was or wasn't granted.
              </div>
            </div>
            <div style={{ display: 'flex', gap: 6, alignItems: 'center' }}>
              <input type="date" value={affDay} onChange={e => { setAffDay(e.target.value); loadAffiliateDay(e.target.value); }} />
              <button className="btn btn-secondary btn-sm" onClick={() => loadAffiliateDay()}>Show</button>
            </div>
          </div>
          {affRows.length === 0 ? (
            <div className="empty-state" style={{ padding: 24 }}><p>Pick a date to see Affiliate residual for that day.</p></div>
          ) : (
            <div className="table-wrap">
              <table>
                <thead><tr><th>Affiliate</th><th style={{ textAlign: 'right' }}>Invoices</th><th style={{ textAlign: 'right' }}>Gross</th><th style={{ textAlign: 'right' }}>Residual</th><th style={{ textAlign: 'right' }}>Threshold</th><th style={{ textAlign: 'right' }}>Units</th><th>Status</th></tr></thead>
                <tbody>
                  {affRows.map(r => (
                    <tr key={r.affiliate_customer_id}>
                      <td style={{ fontWeight: 600 }}>{r.full_name}</td>
                      <td style={{ textAlign: 'right' }}>{r.contributing_invoices}</td>
                      <td style={{ textAlign: 'right' }}>{money(r.contributing_gross)}</td>
                      <td style={{ textAlign: 'right', fontWeight: 600 }}>{money(r.residual)}</td>
                      <td style={{ textAlign: 'right' }}>{r.qualifying_amount != null ? money(r.qualifying_amount) : '—'}</td>
                      <td style={{ textAlign: 'right' }}>{r.units_target}{Number(r.units_existing) > 0 ? ` (${r.units_existing} created)` : ''}</td>
                      <td style={{ fontSize: 12, color: r.reason === 'Qualified.' ? 'var(--success)' : 'var(--text-muted)' }}>{r.reason}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </div>
      )}

      {ruleForm && (
        <Modal title={ruleForm.id ? 'Edit Qualification Rule' : 'New Qualification Rule'} maxWidth={480} onClose={() => setRuleForm(null)}
          footer={<><button className="btn btn-secondary" onClick={() => setRuleForm(null)}>Cancel</button><button className="btn btn-primary" onClick={saveRule} disabled={ruleBusy}>{ruleBusy ? 'Saving…' : 'Save'}</button></>}>
          <div className="form-grid">
            <div className="form-group" style={{ marginBottom: 0 }}>
              <label>Rewards</label>
              <select value={ruleForm.applies_to}
                onChange={e => setRuleForm(f => f && ({ ...f, applies_to: e.target.value,
                  entitlement_kind: e.target.value === 'affiliate' ? 'voucher' : f.entitlement_kind }))}>
                <option value="customer">Customer — the person who spent</option>
                <option value="affiliate">Affiliate — residual after customer units</option>
              </select>
              <div style={{ fontSize: 11, color: 'var(--text-muted)', marginTop: 3 }}>
                {ruleForm.applies_to === 'affiliate'
                  ? 'Affiliate rewards are vouchers only, and apply to the leftover spend after each customer has taken their own units.'
                  : 'Earned by the customer from their own same-day paid total.'}
              </div>
            </div>
            <div className="form-group" style={{ marginBottom: 0 }}>
              <label>Name</label>
              <input value={ruleForm.name} onChange={e => setRuleForm(f => f && ({ ...f, name: e.target.value }))} placeholder="Legacy Qualification" autoFocus />
            </div>
            <div className="form-group" style={{ marginBottom: 0 }}>
              <label>Store</label>
              <select value={ruleForm.store_id} onChange={e => setRuleForm(f => f && ({ ...f, store_id: e.target.value }))}>
                <option value="">All stores</option>
                {stores.map(s => <option key={s.id} value={s.id}>{s.name}</option>)}
              </select>
            </div>
            <div className="form-group" style={{ marginBottom: 0 }}>
              <label>Qualifying amount (S$) *</label>
              <input type="number" min={0} step={0.01} value={ruleForm.qualifying_amount} onChange={e => setRuleForm(f => f && ({ ...f, qualifying_amount: e.target.value }))} placeholder="994.00" />
            </div>
            <div className="form-group" style={{ marginBottom: 0 }}>
              <label>Reward type</label>
              <select value={ruleForm.entitlement_kind} disabled={ruleForm.applies_to === 'affiliate'}
                onChange={e => setRuleForm(f => f && ({ ...f, entitlement_kind: e.target.value }))}>
                {ruleForm.applies_to !== 'affiliate' && <option value="unlimited">Unlimited therapy</option>}
                <option value="voucher">Voucher(s)</option>
              </select>
            </div>
            {ruleForm.entitlement_kind === 'unlimited' ? (
              <div className="form-group" style={{ marginBottom: 0 }}>
                <label>Duration (months)</label>
                <input type="number" min={0} value={ruleForm.duration_months} onChange={e => setRuleForm(f => f && ({ ...f, duration_months: e.target.value }))} placeholder="12" />
              </div>
            ) : (
              <div className="form-group" style={{ marginBottom: 0 }}>
                <label>Voucher quantity per unit</label>
                <input type="number" min={0} value={ruleForm.voucher_qty} onChange={e => setRuleForm(f => f && ({ ...f, voucher_qty: e.target.value }))} placeholder="1" />
              </div>
            )}
            <div className="form-group" style={{ marginBottom: 0 }}>
              <label>Claim window (days)</label>
              <input type="number" min={1} value={ruleForm.activation_deadline_days} onChange={e => setRuleForm(f => f && ({ ...f, activation_deadline_days: e.target.value }))} placeholder="365" />
            </div>
            <div className="form-group" style={{ marginBottom: 0 }}>
              <label>Effective from</label>
              <input type="date" value={ruleForm.effective_date} onChange={e => setRuleForm(f => f && ({ ...f, effective_date: e.target.value }))} />
              <div style={{ fontSize: 11, color: 'var(--text-muted)', marginTop: 3 }}>Backdate this to cover invoices that were already paid, then run Re-check paid days.</div>
            </div>
            <label style={{ display: 'flex', alignItems: 'center', gap: 6, fontSize: 13 }}>
              <input type="checkbox" checked={ruleForm.is_active} style={{ width: 'auto' }} onChange={e => setRuleForm(f => f && ({ ...f, is_active: e.target.checked }))} /> Active
            </label>
            {ruleErr && <div className="alert alert-danger" style={{ marginBottom: 0 }}><span>⚠</span><div>{ruleErr}</div></div>}
          </div>
        </Modal>
      )}

      {actEnt && (
        <Modal title={`Activate — ${actEnt.entitlement_no}`} maxWidth={420} onClose={() => setActEnt(null)}
          footer={<>
            <button className="btn btn-secondary" onClick={() => setActEnt(null)}>Cancel</button>
            <button className="btn btn-secondary" disabled={busy === actEnt.id} onClick={() => doActivate(true)}>Schedule for date</button>
            <button className="btn btn-primary" disabled={busy === actEnt.id} onClick={() => doActivate(false)}>Activate now</button>
          </>}>
          <div className="form-grid">
            <div style={{ fontSize: 12.5, color: 'var(--text-secondary)' }}>
              {cName(actEnt.customer_id)} · {actEnt.package_name} ({actEnt.duration_months} months)<br />
              Must activate by <strong>{d(actEnt.activation_deadline)}</strong>.
            </div>
            <div className="form-group" style={{ marginBottom: 0 }}>
              <label>Activation date (for scheduling)</label>
              <input type="date" value={actDate} min={sgToday()} max={actEnt.activation_deadline} onChange={e => setActDate(e.target.value)} />
              <div style={{ fontSize: 11, color: 'var(--text-muted)', marginTop: 2 }}>"Activate now" starts today. "Schedule for date" uses the date above. Expiry = activation + {actEnt.duration_months} calendar months, locked on activation.</div>
            </div>
          </div>
        </Modal>
      )}

      {pkgModal && (
        <Modal title={pkgModal === 'new' ? 'New Therapy Package' : 'Edit Package'} maxWidth={440} onClose={() => setPkgModal(null)}
          footer={<><button className="btn btn-secondary" onClick={() => setPkgModal(null)}>Cancel</button>
            <button className="btn btn-primary" onClick={savePkg} disabled={busy === 'pkg'}>Save</button></>}>
          <div className="form-grid">
            <div className="form-group" style={{ marginBottom: 0 }}><label>Name *</label><input value={pkgName} onChange={e => setPkgName(e.target.value)} placeholder="e.g. Unlimited Therapy – 1 Year" /></div>
            <div className="form-group" style={{ marginBottom: 0 }}><label>Duration (calendar months) *</label><input type="number" min={1} value={pkgMonths} onChange={e => setPkgMonths(+e.target.value)} /></div>
            <div className="form-group" style={{ marginBottom: 0 }}><label>Description</label><input value={pkgDesc} onChange={e => setPkgDesc(e.target.value)} /></div>
            <label style={{ display: 'flex', alignItems: 'center', gap: 6, fontSize: 13, cursor: 'pointer' }}>
              <input type="checkbox" checked={pkgActive} onChange={e => setPkgActive(e.target.checked)} style={{ width: 'auto' }} /> Active
            </label>
          </div>
        </Modal>
      )}

      {reschedEnt && reschedDate === null && (
        <DateModal title={`Reschedule — ${reschedEnt.entitlement_no}`} label="New scheduled date"
          initial={reschedEnt.scheduled_date ?? sgToday()} min={sgToday()} max={reschedEnt.activation_deadline}
          confirmLabel="Next" helpText={`Must be on or before the deadline ${d(reschedEnt.activation_deadline)}.`}
          onClose={() => setReschedEnt(null)} onSubmit={(dt) => setReschedDate(dt)} />
      )}
      {reschedEnt && reschedDate !== null && (
        <ReasonModal title="Reason for date change" label="Reason for the date change"
          confirmLabel="Save" onClose={() => { setReschedEnt(null); setReschedDate(null); }}
          onSubmit={(reason) => submitReschedule(reschedEnt, reschedDate, reason)} />
      )}
      {refundEnt && (
        <ReasonModal title={`Refund — ${refundEnt.entitlement_no}`} label="Refund reason"
          placeholder="Why is this being refunded? (allowed only before activation)"
          confirmLabel="Refund" onClose={() => setRefundEnt(null)}
          onSubmit={(reason) => submitRefund(refundEnt, reason)} />
      )}
      {priceFor && (
        <StorePriceEditor kind="therapy" targetId={priceFor.id} targetName={priceFor.name}
          stores={stores} onClose={() => setPriceFor(null)} />
      )}
    </div>
  );
};

export default TherapyPage;
