import React, { useEffect, useState, useCallback, useMemo } from 'react';
import { supabase, fetchCustomersByIds, mergeCustomers} from '../lib/supabase';
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
  const [tab, setTab] = useState<'purchased' | 'legacy' | 'packages' | 'qualification' | 'credit' | 'bundles'>('purchased');
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
  const [pkgName, setPkgName] = useState(''); const [pkgSku, setPkgSku] = useState(''); const [pkgMonths, setPkgMonths] = useState(12);
  const [pkgDesc, setPkgDesc] = useState(''); const [pkgActive, setPkgActive] = useState(true);
  const [priceFor, setPriceFor] = useState<{ id: string; name: string } | null>(null);
  const [reschedEnt, setReschedEnt] = useState<PurchasedTherapyEntitlement | null>(null);
  const [reschedDate, setReschedDate] = useState<string | null>(null);   // step 1 result -> step 2 asks reason
  const [refundEnt, setRefundEnt] = useState<PurchasedTherapyEntitlement | null>(null);

  // Same-day qualification rules (Phase 22).
  const [rules, setRules] = useState<any[]>([]);
  const [creditPkgs, setCreditPkgs] = useState<any[]>([]);
  const [bundles, setBundles] = useState<any[]>([]);
  const emptyBundle = { id: null as string | null, name: '', sku: '', grants_reward: false, customer_payment_amount: '',
    paid_credit_amount: '', bonus_credit_amount: '', free_voucher_qty: '',
    reward_qualifying_amount: '', is_active: true, effective_from: '', effective_to: '',
    commission_classification: 'third_party', tier1_rate: '', tier2_rate: '',
    store_ids: [] as string[], voucher_ids: [] as string[] };
  const [bundleForm, setBundleForm] = useState<typeof emptyBundle | null>(null);
  const [bundleBusy, setBundleBusy] = useState(false);
  const [bundleErr, setBundleErr] = useState<string | null>(null);
  const saveBundle = async () => {
    if (!bundleForm) return;
    setBundleBusy(true); setBundleErr(null);
    const { data, error } = await supabase.rpc('upsert_premium_bundle', {
      p_id: bundleForm.id, p_name: bundleForm.name,
      p_customer_payment_amount: Number(bundleForm.customer_payment_amount || 0),
      p_paid_credit_amount: Number(bundleForm.paid_credit_amount || 0),
      p_bonus_credit_amount: Number(bundleForm.bonus_credit_amount || 0),
      p_free_voucher_qty: bundleForm.free_voucher_qty === '' ? null : Number(bundleForm.free_voucher_qty),
      p_reward_qualifying_amount: bundleForm.reward_qualifying_amount === '' ? null : Number(bundleForm.reward_qualifying_amount),
      p_is_active: bundleForm.is_active,
      p_effective_from: bundleForm.effective_from || null,
      p_effective_to: bundleForm.effective_to || null,
      p_commission_classification: bundleForm.commission_classification,
      p_staff_commission_enabled: true, p_staff_commission_rate: null,
      p_tier1_rate: bundleForm.tier1_rate === '' ? null : Number(bundleForm.tier1_rate),
      p_tier2_rate: bundleForm.tier2_rate === '' ? null : Number(bundleForm.tier2_rate),
      p_notes: null,
      p_store_ids: bundleForm.store_ids.length ? bundleForm.store_ids : null,
      p_voucher_ids: bundleForm.voucher_ids.length ? bundleForm.voucher_ids : null,
    });
    setBundleBusy(false);
    if (error) { setBundleErr(error.message); return; }
    if (data) {
      const { error: sErr } = await supabase.rpc('set_catalogue_sku',
        { p_kind: 'premium_bundle', p_id: data, p_sku: bundleForm.sku || null });
      if (sErr) { setBundleErr(sErr.message); return; }
      const { error: rErr } = await supabase.rpc('set_catalogue_reward',
        { p_kind: 'premium_bundle', p_id: data, p_grants: bundleForm.grants_reward });
      if (rErr) { setBundleErr(rErr.message); return; }
    }
    setBundleForm(null); load();
  };
  const [allVouchers, setAllVouchers] = useState<any[]>([]);
  const emptyPkg = { id: null as string | null, name: '', sku: '', grants_reward: false, customer_price: '', paid_credit_amount: '',
    is_active: true, effective_from: '', effective_to: '', commission_classification: 'own',
    staff_commission_enabled: true, tier1_rate: '', tier2_rate: '', reward_qualifying_amount: '',
    store_ids: [] as string[], voucher_ids: [] as string[] };
  const [pkgForm, setPkgForm] = useState<typeof emptyPkg | null>(null);
  const [pkgBusy, setPkgBusy] = useState(false);
  const [pkgErr, setPkgErr] = useState<string | null>(null);
  const saveCreditPkg = async () => {
    if (!pkgForm) return;
    setPkgBusy(true); setPkgErr(null);
    const { data, error } = await supabase.rpc('upsert_credit_package', {
      p_id: pkgForm.id, p_name: pkgForm.name,
      p_customer_price: Number(pkgForm.customer_price || 0),
      p_paid_credit_amount: Number(pkgForm.paid_credit_amount || 0),
      p_is_active: pkgForm.is_active,
      p_effective_from: pkgForm.effective_from || null,
      p_effective_to: pkgForm.effective_to || null,
      p_commission_classification: pkgForm.commission_classification,
      p_staff_commission_enabled: pkgForm.staff_commission_enabled,
      p_staff_commission_rate: null,
      p_tier1_rate: pkgForm.tier1_rate === '' ? null : Number(pkgForm.tier1_rate),
      p_tier2_rate: pkgForm.tier2_rate === '' ? null : Number(pkgForm.tier2_rate),
      p_reward_qualifying_amount: pkgForm.reward_qualifying_amount === '' ? null : Number(pkgForm.reward_qualifying_amount),
      p_notes: null,
      p_store_ids: pkgForm.store_ids.length ? pkgForm.store_ids : null,
      p_voucher_ids: pkgForm.voucher_ids.length ? pkgForm.voucher_ids : null,
    });
    setPkgBusy(false);
    if (error) { setPkgErr(error.message); return; }
    if (data) {
      const { error: sErr } = await supabase.rpc('set_catalogue_sku',
        { p_kind: 'credit_package', p_id: data, p_sku: pkgForm.sku || null });
      if (sErr) { setPkgErr(sErr.message); return; }
      const { error: rErr } = await supabase.rpc('set_catalogue_reward',
        { p_kind: 'credit_package', p_id: data, p_grants: pkgForm.grants_reward });
      if (rErr) { setPkgErr(rErr.message); return; }
    }
    setPkgForm(null); load();
  };
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
    const baseCustomers = (cu.data as Customer[]) ?? [];
    setCustomers(baseCustomers);
    // The customer table is capped at 1000 rows per request, so records
    // belonging to customers outside that set would show no name. Fetch the
    // ones actually referenced here.
    void (async () => {
      const extra = await fetchCustomersByIds([...((pe.data as any[]) ?? []).map(x => x.customer_id), ...((le.data as any[]) ?? []).map(x => x.customer_id)]);
      setCustomers(cur => mergeCustomers(cur, extra));
    })();
    setRules((ru.data as any[]) ?? []);
    const { data: st2 } = await supabase.rpc('legacy_setup_status');
    setSetupStatus(st2 ?? null);
    const { data: cp } = await supabase.from('credit_packages').select('*').is('deleted_at', null).order('customer_price');
    setCreditPkgs((cp as any[]) ?? []);
    const { data: pb } = await supabase.from('premium_bundles').select('*').is('deleted_at', null).order('customer_payment_amount', { ascending: false });
    setBundles((pb as any[]) ?? []);
    const { data: vc } = await supabase.from('vouchers').select('id,name,code').is('deleted_at', null).eq('is_active', true).order('name');
    setAllVouchers((vc as any[]) ?? []);
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
    setPkgSku(p === 'new' ? '' : ((p as any).sku ?? ''));
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
    if (error) { setBusy(null); setErr(error.message); return; }
    // The SKU is stored separately so the upsert signature stays stable.
    const pkgId = pkgModal === 'new' ? null : (pkgModal as UnlimitedTherapyPackage).id;
    if (pkgId) {
      const { error: sErr } = await supabase.rpc('set_catalogue_sku',
        { p_kind: 'therapy', p_id: pkgId, p_sku: pkgSku || null });
      if (sErr) { setBusy(null); setErr(sErr.message); return; }
    }
    setBusy(null);
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
        {([['purchased', 'Purchased'], ['legacy', 'Legacy Therapy'], ...(canManage ? [['qualification', 'Qualification'], ['credit', 'Credit Packages'], ['bundles', 'Premium Bundles'], ['packages', 'Packages']] : [])] as [typeof tab, string][]).map(([v, l]) => (
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
                <thead><tr><th>Name</th><th>SKU</th><th>Duration</th><th>Description</th><th>Active</th><th></th></tr></thead>
                <tbody>
                  {packages.map(p => (
                    <tr key={p.id}>
                      <td style={{ fontWeight: 600 }}>{p.name}</td>
                      <td style={{ fontSize: 12, color: 'var(--text-muted)' }}>{(p as any).sku ?? '—'}</td>
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

      {tab === 'bundles' && canManage && (
        <>
          <div style={{ marginBottom: 12, display: 'flex', justifyContent: 'space-between', alignItems: 'center', flexWrap: 'wrap', gap: 8 }}>
            <div style={{ fontSize: 12.5, color: 'var(--text-muted)', maxWidth: 640 }}>
              A Premium Bundle is its own catalogue, separate from Promotions. The customer pays once and receives Paid Credit, Bonus Credit and a quantity of free reward vouchers issued immediately at payment. Bundle rewards are vouchers only — there is no Therapy-month choice. Commission uses the third-party rate on external money only.
            </div>
            <button className="btn btn-primary" onClick={() => { setBundleForm({ ...emptyBundle }); setBundleErr(null); }}><Plus size={16} /> New Bundle</button>
          </div>
          <div className="card">
            {bundles.length === 0 ? <div className="empty-state" style={{ padding: 40 }}><p>No premium bundles yet.</p></div> : (
              <div className="table-wrap">
                <table>
                  <thead><tr><th>Name</th><th>SKU</th><th>Reward</th><th style={{ textAlign: 'right' }}>Pays</th><th style={{ textAlign: 'right' }}>Paid Credit</th><th style={{ textAlign: 'right' }}>Bonus</th><th style={{ textAlign: 'right' }}>Vouchers</th><th>Commission</th><th style={{ textAlign: 'right' }}>Tier 1 / 2</th><th>Active</th><th></th></tr></thead>
                  <tbody>
                    {bundles.map(b => (
                      <tr key={b.id}>
                        <td style={{ fontWeight: 600 }}>{b.name}</td>
                        <td style={{ fontSize: 12, color: 'var(--text-muted)' }}>{b.sku ?? '—'}</td>
                        <td>{b.grants_reward ? <span className="badge badge-accent">{b.free_voucher_qty} vouchers</span> : <span className="badge badge-muted">None</span>}</td>
                        <td style={{ textAlign: 'right' }}>{money(b.customer_payment_amount)}</td>
                        <td style={{ textAlign: 'right' }}>{money(b.paid_credit_amount)}</td>
                        <td style={{ textAlign: 'right' }}>{money(b.bonus_credit_amount)}</td>
                        <td style={{ textAlign: 'right', fontWeight: 600 }}>{b.free_voucher_qty}</td>
                        <td style={{ fontSize: 12 }}>{b.commission_classification === 'third_party' ? 'Third-party' : 'Own'}</td>
                        <td style={{ textAlign: 'right', fontSize: 12 }}>{b.tier1_rate ?? 'default'} / {b.tier2_rate ?? 'default'}</td>
                        <td>{b.is_active ? <span className="badge badge-success">Active</span> : <span className="badge badge-muted">Inactive</span>}</td>
                        <td><button className="btn btn-secondary btn-sm btn-icon" onClick={async () => {
                          const { data: st4 } = await supabase.from('premium_bundle_stores').select('store_id').eq('bundle_id', b.id);
                          const { data: vs2 } = await supabase.from('premium_bundle_vouchers').select('voucher_id').eq('bundle_id', b.id);
                          setBundleErr(null);
                          setBundleForm({ id: b.id, name: b.name ?? '', sku: b.sku ?? '', grants_reward: !!b.grants_reward,
                            customer_payment_amount: String(b.customer_payment_amount ?? ''),
                            paid_credit_amount: String(b.paid_credit_amount ?? ''),
                            bonus_credit_amount: String(b.bonus_credit_amount ?? ''),
                            free_voucher_qty: String(b.free_voucher_qty ?? ''),
                            reward_qualifying_amount: b.reward_qualifying_amount != null ? String(b.reward_qualifying_amount) : '',
                            is_active: b.is_active, effective_from: b.effective_from ?? '', effective_to: b.effective_to ?? '',
                            commission_classification: b.commission_classification ?? 'third_party',
                            tier1_rate: b.tier1_rate != null ? String(b.tier1_rate) : '',
                            tier2_rate: b.tier2_rate != null ? String(b.tier2_rate) : '',
                            store_ids: ((st4 as any[]) ?? []).map(x => x.store_id),
                            voucher_ids: ((vs2 as any[]) ?? []).map(x => x.voucher_id) });
                        }}><Pencil size={13} /></button></td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </div>
        </>
      )}

      {bundleForm && (
        <Modal title={bundleForm.id ? 'Edit Premium Bundle' : 'New Premium Bundle'} maxWidth={560} onClose={() => setBundleForm(null)}
          footer={<><button className="btn btn-secondary" onClick={() => setBundleForm(null)}>Cancel</button>
            <button className="btn btn-primary" onClick={saveBundle} disabled={bundleBusy}>{bundleBusy ? 'Saving…' : 'Save'}</button></>}>
          <div className="form-grid">
            <div className="form-group" style={{ marginBottom: 0 }}>
              <label>Bundle name *</label>
              <input value={bundleForm.name} onChange={e => setBundleForm(f => f && ({ ...f, name: e.target.value }))} placeholder="Bundle A" autoFocus />
            </div>
            <div className="form-group" style={{ marginBottom: 0 }}>
              <label>SKU</label>
              <input value={bundleForm.sku} onChange={e => setBundleForm(f => f && ({ ...f, sku: e.target.value }))} placeholder="e.g. PB-15000" />
            </div>
            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 10 }}>
              <div className="form-group" style={{ marginBottom: 0 }}>
                <label>Customer pays (S$) *</label>
                <input type="number" min={0} step={0.01} value={bundleForm.customer_payment_amount} onChange={e => setBundleForm(f => f && ({ ...f, customer_payment_amount: e.target.value }))} />
              </div>
              <div className="form-group" style={{ marginBottom: 0 }}>
                <label>Paid Credit (S$)</label>
                <input type="number" min={0} step={0.01} value={bundleForm.paid_credit_amount} onChange={e => setBundleForm(f => f && ({ ...f, paid_credit_amount: e.target.value }))} />
              </div>
              <div className="form-group" style={{ marginBottom: 0 }}>
                <label>Bonus Credit (S$)</label>
                <input type="number" min={0} step={0.01} value={bundleForm.bonus_credit_amount} onChange={e => setBundleForm(f => f && ({ ...f, bonus_credit_amount: e.target.value }))} />
              </div>
              <div className="form-group" style={{ marginBottom: 0 }}>
                <label>Free vouchers</label>
                <input type="number" min={0} value={bundleForm.free_voucher_qty} onChange={e => setBundleForm(f => f && ({ ...f, free_voucher_qty: e.target.value }))} placeholder="auto from payment" />
              </div>
              <div className="form-group" style={{ marginBottom: 0 }}>
                <label>Reward threshold (S$)</label>
                <input type="number" min={0} step={0.01} value={bundleForm.reward_qualifying_amount} onChange={e => setBundleForm(f => f && ({ ...f, reward_qualifying_amount: e.target.value }))} placeholder="994" />
              </div>
              <div className="form-group" style={{ marginBottom: 0 }}>
                <label>Commission classification</label>
                <select value={bundleForm.commission_classification} onChange={e => setBundleForm(f => f && ({ ...f, commission_classification: e.target.value }))}>
                  <option value="third_party">Third-party rate</option>
                  <option value="own">Own product rate</option>
                </select>
              </div>
              <div className="form-group" style={{ marginBottom: 0 }}>
                <label>Tier 1 rate (%)</label>
                <input type="number" min={0} max={100} step={0.1} value={bundleForm.tier1_rate} onChange={e => setBundleForm(f => f && ({ ...f, tier1_rate: e.target.value }))} placeholder="default" />
              </div>
              <div className="form-group" style={{ marginBottom: 0 }}>
                <label>Tier 2 rate (%)</label>
                <input type="number" min={0} max={100} step={0.1} value={bundleForm.tier2_rate} onChange={e => setBundleForm(f => f && ({ ...f, tier2_rate: e.target.value }))} placeholder="default" />
              </div>
              <div className="form-group" style={{ marginBottom: 0 }}>
                <label>Effective from</label>
                <input type="date" value={bundleForm.effective_from} onChange={e => setBundleForm(f => f && ({ ...f, effective_from: e.target.value }))} />
              </div>
              <div className="form-group" style={{ marginBottom: 0 }}>
                <label>Effective to</label>
                <input type="date" value={bundleForm.effective_to} onChange={e => setBundleForm(f => f && ({ ...f, effective_to: e.target.value }))} />
              </div>
            </div>
            <div className="form-group" style={{ marginBottom: 0 }}>
              <label>Available at stores</label>
              <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8 }}>
                {stores.map(s3 => (
                  <label key={s3.id} style={{ display: 'flex', gap: 5, alignItems: 'center', fontSize: 12.5 }}>
                    <input type="checkbox" style={{ width: 'auto' }} checked={bundleForm.store_ids.includes(s3.id)}
                      onChange={e => setBundleForm(f => f && ({ ...f, store_ids: e.target.checked ? [...f.store_ids, s3.id] : f.store_ids.filter(x => x !== s3.id) }))} />
                    {s3.name}
                  </label>
                ))}
              </div>
              <div style={{ fontSize: 11, color: 'var(--text-muted)', marginTop: 3 }}>Leave all unticked to allow every store.</div>
            </div>
            <div className="form-group" style={{ marginBottom: 0 }}>
              <label>Eligible voucher choices *</label>
              <div style={{ maxHeight: 150, overflowY: 'auto', border: '1px solid var(--border)', borderRadius: 'var(--radius-sm)', padding: 8 }}>
                {allVouchers.map(v => (
                  <label key={v.id} style={{ display: 'flex', gap: 6, alignItems: 'center', fontSize: 12.5, padding: '2px 0' }}>
                    <input type="checkbox" style={{ width: 'auto' }} checked={bundleForm.voucher_ids.includes(v.id)}
                      onChange={e => setBundleForm(f => f && ({ ...f, voucher_ids: e.target.checked ? [...f.voucher_ids, v.id] : f.voucher_ids.filter(x => x !== v.id) }))} />
                    {v.name}
                  </label>
                ))}
              </div>
              <div style={{ fontSize: 11, color: 'var(--text-muted)', marginTop: 3 }}>The customer may mix any of these up to the free quantity.</div>
            </div>
            <div>
              <label style={{ display: 'flex', alignItems: 'center', gap: 6, fontSize: 13 }}>
                <input type="checkbox" checked={bundleForm.grants_reward} style={{ width: 'auto' }}
                  onChange={e => setBundleForm(f => f && ({ ...f, grants_reward: e.target.checked }))} /> Also grant free reward vouchers
              </label>
              <div style={{ fontSize: 11, color: 'var(--text-muted)', marginTop: 3 }}>
                Off by default: the customer receives the Paid and Bonus Credit only, and no voucher selection is needed at the till.
              </div>
            </div>
            <label style={{ display: 'flex', alignItems: 'center', gap: 6, fontSize: 13 }}>
              <input type="checkbox" checked={bundleForm.is_active} style={{ width: 'auto' }} onChange={e => setBundleForm(f => f && ({ ...f, is_active: e.target.checked }))} /> Active
            </label>
            {bundleErr && <div className="alert alert-danger" style={{ marginBottom: 0 }}><span>⚠</span><div>{bundleErr}</div></div>}
          </div>
        </Modal>
      )}

      {tab === 'credit' && canManage && (
        <>
          <div style={{ marginBottom: 12, display: 'flex', justifyContent: 'space-between', alignItems: 'center', flexWrap: 'wrap', gap: 8 }}>
            <div style={{ fontSize: 12.5, color: 'var(--text-muted)', maxWidth: 640 }}>
              A customer pays for a Credit Package and receives Paid Credit that may only be spent on the package's eligible Therapy Vouchers, plus one free reward unit for every whole qualifying amount of credit. The package line itself can never be paid with wallet credit.
            </div>
            <button className="btn btn-primary" onClick={() => { setPkgForm({ ...emptyPkg }); setPkgErr(null); }}><Plus size={16} /> New Package</button>
          </div>
          <div className="card">
            {creditPkgs.length === 0 ? <div className="empty-state" style={{ padding: 40 }}><p>No credit packages yet.</p></div> : (
              <div className="table-wrap">
                <table>
                  <thead><tr><th>Name</th><th>SKU</th><th>Reward</th><th style={{ textAlign: 'right' }}>Price</th><th style={{ textAlign: 'right' }}>Credit</th><th>Commission</th><th style={{ textAlign: 'right' }}>Tier 1 / 2</th><th>Effective</th><th>Active</th><th></th></tr></thead>
                  <tbody>
                    {creditPkgs.map(p2 => (
                      <tr key={p2.id}>
                        <td style={{ fontWeight: 600 }}>{p2.name}</td>
                        <td style={{ fontSize: 12, color: 'var(--text-muted)' }}>{p2.sku ?? '—'}</td>
                        <td>{p2.grants_reward ? <span className="badge badge-accent">Yes</span> : <span className="badge badge-muted">None</span>}</td>
                        <td style={{ textAlign: 'right' }}>{money(p2.customer_price)}</td>
                        <td style={{ textAlign: 'right' }}>{money(p2.paid_credit_amount)}</td>
                        <td style={{ fontSize: 12 }}>{p2.commission_classification === 'third_party' ? 'Third-party' : 'Own'}</td>
                        <td style={{ textAlign: 'right', fontSize: 12 }}>{p2.tier1_rate ?? 'default'} / {p2.tier2_rate ?? 'default'}</td>
                        <td style={{ fontSize: 12 }}>{d(p2.effective_from)}{p2.effective_to ? ` → ${d(p2.effective_to)}` : ''}</td>
                        <td>{p2.is_active ? <span className="badge badge-success">Active</span> : <span className="badge badge-muted">Inactive</span>}</td>
                        <td><button className="btn btn-secondary btn-sm btn-icon" onClick={async () => {
                          const { data: st3 } = await supabase.from('credit_package_stores').select('store_id').eq('package_id', p2.id);
                          const { data: vs } = await supabase.from('credit_package_vouchers').select('voucher_id').eq('package_id', p2.id);
                          setPkgErr(null);
                          setPkgForm({ id: p2.id, name: p2.name ?? '', sku: p2.sku ?? '', grants_reward: !!p2.grants_reward, customer_price: String(p2.customer_price ?? ''),
                            paid_credit_amount: String(p2.paid_credit_amount ?? ''), is_active: p2.is_active,
                            effective_from: p2.effective_from ?? '', effective_to: p2.effective_to ?? '',
                            commission_classification: p2.commission_classification ?? 'own',
                            staff_commission_enabled: p2.staff_commission_enabled ?? true,
                            tier1_rate: p2.tier1_rate != null ? String(p2.tier1_rate) : '',
                            tier2_rate: p2.tier2_rate != null ? String(p2.tier2_rate) : '',
                            reward_qualifying_amount: p2.reward_qualifying_amount != null ? String(p2.reward_qualifying_amount) : '',
                            store_ids: ((st3 as any[]) ?? []).map(x => x.store_id),
                            voucher_ids: ((vs as any[]) ?? []).map(x => x.voucher_id) });
                        }}><Pencil size={13} /></button></td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </div>
        </>
      )}

      {pkgForm && (
        <Modal title={pkgForm.id ? 'Edit Credit Package' : 'New Credit Package'} maxWidth={540} onClose={() => setPkgForm(null)}
          footer={<><button className="btn btn-secondary" onClick={() => setPkgForm(null)}>Cancel</button>
            <button className="btn btn-primary" onClick={saveCreditPkg} disabled={pkgBusy}>{pkgBusy ? 'Saving…' : 'Save'}</button></>}>
          <div className="form-grid">
            <div className="form-group" style={{ marginBottom: 0 }}>
              <label>Package name *</label>
              <input value={pkgForm.name} onChange={e => setPkgForm(f => f && ({ ...f, name: e.target.value }))} placeholder="$1,000 Credit Package" autoFocus />
            </div>
            <div className="form-group" style={{ marginBottom: 0 }}>
              <label>SKU</label>
              <input value={pkgForm.sku} onChange={e => setPkgForm(f => f && ({ ...f, sku: e.target.value }))} placeholder="e.g. CP-1000" />
            </div>
            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 10 }}>
              <div className="form-group" style={{ marginBottom: 0 }}>
                <label>Customer price (S$) *</label>
                <input type="number" min={0} step={0.01} value={pkgForm.customer_price} onChange={e => setPkgForm(f => f && ({ ...f, customer_price: e.target.value }))} />
              </div>
              <div className="form-group" style={{ marginBottom: 0 }}>
                <label>Paid Credit received (S$) *</label>
                <input type="number" min={0} step={0.01} value={pkgForm.paid_credit_amount} onChange={e => setPkgForm(f => f && ({ ...f, paid_credit_amount: e.target.value }))} />
              </div>
              <div className="form-group" style={{ marginBottom: 0 }}>
                <label>Commission classification</label>
                <select value={pkgForm.commission_classification} onChange={e => setPkgForm(f => f && ({ ...f, commission_classification: e.target.value }))}>
                  <option value="own">Own product rate</option>
                  <option value="third_party">Third-party rate</option>
                </select>
              </div>
              <div className="form-group" style={{ marginBottom: 0 }}>
                <label>Reward threshold (S$)</label>
                <input type="number" min={0} step={0.01} value={pkgForm.reward_qualifying_amount} onChange={e => setPkgForm(f => f && ({ ...f, reward_qualifying_amount: e.target.value }))} placeholder="defaults to the Legacy tier" />
              </div>
              <div className="form-group" style={{ marginBottom: 0 }}>
                <label>Tier 1 rate (%)</label>
                <input type="number" min={0} max={100} step={0.1} value={pkgForm.tier1_rate} onChange={e => setPkgForm(f => f && ({ ...f, tier1_rate: e.target.value }))} placeholder="default" />
              </div>
              <div className="form-group" style={{ marginBottom: 0 }}>
                <label>Tier 2 rate (%)</label>
                <input type="number" min={0} max={100} step={0.1} value={pkgForm.tier2_rate} onChange={e => setPkgForm(f => f && ({ ...f, tier2_rate: e.target.value }))} placeholder="default" />
              </div>
              <div className="form-group" style={{ marginBottom: 0 }}>
                <label>Effective from</label>
                <input type="date" value={pkgForm.effective_from} onChange={e => setPkgForm(f => f && ({ ...f, effective_from: e.target.value }))} />
              </div>
              <div className="form-group" style={{ marginBottom: 0 }}>
                <label>Effective to</label>
                <input type="date" value={pkgForm.effective_to} onChange={e => setPkgForm(f => f && ({ ...f, effective_to: e.target.value }))} />
              </div>
            </div>
            <div className="form-group" style={{ marginBottom: 0 }}>
              <label>Available at stores</label>
              <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8 }}>
                {stores.map(s2 => (
                  <label key={s2.id} style={{ display: 'flex', gap: 5, alignItems: 'center', fontSize: 12.5 }}>
                    <input type="checkbox" style={{ width: 'auto' }} checked={pkgForm.store_ids.includes(s2.id)}
                      onChange={e => setPkgForm(f => f && ({ ...f, store_ids: e.target.checked ? [...f.store_ids, s2.id] : f.store_ids.filter(x => x !== s2.id) }))} />
                    {s2.name}
                  </label>
                ))}
              </div>
              <div style={{ fontSize: 11, color: 'var(--text-muted)', marginTop: 3 }}>Leave all unticked to allow every store.</div>
            </div>
            <div className="form-group" style={{ marginBottom: 0 }}>
              <label>Eligible voucher choices *</label>
              <div style={{ maxHeight: 150, overflowY: 'auto', border: '1px solid var(--border)', borderRadius: 'var(--radius-sm)', padding: 8 }}>
                {allVouchers.map(v => (
                  <label key={v.id} style={{ display: 'flex', gap: 6, alignItems: 'center', fontSize: 12.5, padding: '2px 0' }}>
                    <input type="checkbox" style={{ width: 'auto' }} checked={pkgForm.voucher_ids.includes(v.id)}
                      onChange={e => setPkgForm(f => f && ({ ...f, voucher_ids: e.target.checked ? [...f.voucher_ids, v.id] : f.voucher_ids.filter(x => x !== v.id) }))} />
                    {v.name}
                  </label>
                ))}
              </div>
              <div style={{ fontSize: 11, color: 'var(--text-muted)', marginTop: 3 }}>The package's credit can only be spent on these vouchers.</div>
            </div>
            <div>
              <label style={{ display: 'flex', alignItems: 'center', gap: 6, fontSize: 13 }}>
                <input type="checkbox" checked={pkgForm.grants_reward} style={{ width: 'auto' }}
                  onChange={e => setPkgForm(f => f && ({ ...f, grants_reward: e.target.checked }))} /> Also grant a qualification reward
              </label>
              <div style={{ fontSize: 11, color: 'var(--text-muted)', marginTop: 3 }}>
                Off by default: the customer receives the credit only. Tick this to also grant one free Legacy reward unit per whole reward threshold.
              </div>
            </div>
            <label style={{ display: 'flex', alignItems: 'center', gap: 6, fontSize: 13 }}>
              <input type="checkbox" checked={pkgForm.is_active} style={{ width: 'auto' }} onChange={e => setPkgForm(f => f && ({ ...f, is_active: e.target.checked }))} /> Active
            </label>
            {pkgErr && <div className="alert alert-danger" style={{ marginBottom: 0 }}><span>⚠</span><div>{pkgErr}</div></div>}
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
            <div className="form-group" style={{ marginBottom: 0 }}><label>SKU</label><input value={pkgSku} onChange={e => setPkgSku(e.target.value)} placeholder="e.g. TH-12M" /></div>
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
