import React, { useEffect, useState, useCallback, useMemo } from 'react';
import { supabase } from '../lib/supabase';
import { useAuth } from '../context/AuthContext';
import { StaffCommission, StaffCommissionPayout, Profile, PaymentMethod, isOwnerOrManager, isManagerOrAbove } from '../types';
import { Modal, NoAccess } from '../components/ui';
import { RefreshCw, Coins, Wallet, Settings, Download } from 'lucide-react';
import { ExcelExportButton } from '../components/ExcelExport';

const money = (n: number) => `S$${n.toFixed(2)}`;
const monthKey = (d: string) => new Date(d).toLocaleDateString(undefined, { year: 'numeric', month: 'short' });

const StaffCommissionsPage: React.FC = () => {
  const { profile } = useAuth();
  // Access is checked AFTER the hooks below. Returning early here would call
  // no hooks on the first render and every hook on the next, which React
  // treats as a fatal error and blanks the whole app.
  const hasAccess = isManagerOrAbove(profile?.role);
  const canPay = isOwnerOrManager(profile?.role);

  const [tab, setTab] = useState<'earned' | 'payouts'>('earned');
  const [commissions, setCommissions] = useState<StaffCommission[]>([]);
  const [payouts, setPayouts] = useState<StaffCommissionPayout[]>([]);
  const [profiles, setProfiles] = useState<Profile[]>([]);
  const [methods, setMethods] = useState<PaymentMethod[]>([]);
  const [rate, setRate] = useState<number>(3);
  const [loading, setLoading] = useState(true);

  const load = useCallback(async () => {
    setLoading(true);
    const [sc, pay, prof, pm, st] = await Promise.all([
      supabase.from('staff_commissions').select('*').order('invoice_paid_date', { ascending: false }),
      supabase.from('staff_commission_payouts').select('*').order('paid_at', { ascending: false }),
      supabase.from('profiles').select('id,full_name,role,work_phone,is_active').is('deleted_at', null),
      supabase.from('payment_methods').select('*').is('deleted_at', null).eq('is_active', true).order('name'),
      supabase.from('app_settings').select('staff_commission_rate').eq('id', true).single(),
    ]);
    setCommissions((sc.data as StaffCommission[]) ?? []);
    setPayouts((pay.data as StaffCommissionPayout[]) ?? []);
    setProfiles((prof.data as Profile[]) ?? []);
    setMethods((pm.data as PaymentMethod[]) ?? []);
    if (st.data) setRate(Number((st.data as any).staff_commission_rate));
    setLoading(false);
  }, []);
  useEffect(() => { load(); }, [load]);

  const sName = (id: string) => profiles.find(p => p.id === id)?.full_name ?? '—';
  const mName = (id: string | null) => id ? (methods.find(m => m.id === id)?.name ?? '—') : '—';

  // Unpaid grouped by staff + month.
  const earnedGroups = useMemo(() => {
    const map = new Map<string, { staff_id: string; month: string; total: number; count: number }>();
    commissions.filter(c => c.status === 'earned' && !c.payout_id && c.invoice_paid_date).forEach(c => {
      const mk = (c.invoice_paid_date as string).slice(0, 7);
      const key = `${c.staff_id}|${mk}`;
      const g = map.get(key) ?? { staff_id: c.staff_id, month: mk, total: 0, count: 0 };
      g.total += Number(c.commission_amount); g.count += 1; map.set(key, g);
    });
    return Array.from(map.values()).sort((a, b) => b.month.localeCompare(a.month) || b.total - a.total);
  }, [commissions]);

  const unpaidTotal = earnedGroups.reduce((s, g) => s + g.total, 0);

  // Pay modal
  const [payFor, setPayFor] = useState<{ staff_id: string; month: string; total: number } | null>(null);
  const [payMethod, setPayMethod] = useState(''); const [payRef, setPayRef] = useState('');
  const [payBusy, setPayBusy] = useState(false); const [payErr, setPayErr] = useState<string | null>(null);
  const submitPay = async () => {
    if (!payFor) return;
    setPayBusy(true); setPayErr(null);
    const { error } = await supabase.rpc('create_staff_commission_payout', {
      p_staff_id: payFor.staff_id, p_month: `${payFor.month}-01`,
      p_payment_method_id: payMethod || null, p_reference: payRef.trim() || null, p_notes: null,
    });
    setPayBusy(false);
    if (error) { setPayErr(error.message); return; }
    setPayFor(null); load();
  };

  // Rate settings
  const [rateOpen, setRateOpen] = useState(false);
  const [rateDraft, setRateDraft] = useState(3);
  const [rateBusy, setRateBusy] = useState(false);
  const saveRate = async () => {
    setRateBusy(true);
    const { error } = await supabase.rpc('set_staff_commission_rate', { p_rate: rateDraft });
    setRateBusy(false);
    if (error) { alert(error.message); return; }
    setRateOpen(false); load();
  };


  if (!hasAccess) return <NoAccess message="Only Owners, Admins, and Managers can view staff commissions." />;


  return (
    <div>
      <div className="page-header">
        <div><h2>Staff Commissions</h2><p>Service staff earn an equal share of {rate}% of each paid invoice they served. Unpaid total: <strong>{money(unpaidTotal)}</strong></p></div>
        <div style={{ display: 'flex', gap: 10 }}>
          <ExcelExportButton
            rows={tab === 'earned' ? earnedGroups : payouts}
            filename={`staff-commissions-${tab}`} sheetName="Staff Commissions"
            dateOf={tab === 'payouts' ? ((p: any) => p.created_at) : undefined}
            dateLabel="Payout date"
            columns={tab === 'earned' ? [
              { header: 'Staff', value: (g: any) => g.staff_name ?? '' },
              { header: 'Total', value: (g: any) => Number(g.total ?? 0) },
            ] : [
              { header: 'Date', value: (p: any) => new Date(p.created_at).toLocaleDateString('en-GB') },
              { header: 'Staff', value: (p: any) => p.staff_name ?? '' },
              { header: 'Amount', value: (p: any) => Number(p.amount ?? 0) },
            ]} />
          {canPay && <button className="btn btn-secondary" onClick={() => { setRateDraft(rate); setRateOpen(true); }}><Settings size={15} /> Rate</button>}
          <button className="btn btn-secondary" onClick={load}><RefreshCw size={15} className={loading ? 'spin' : ''} /> Refresh</button>
        </div>
      </div>

      <div style={{ display: 'flex', gap: 6, marginBottom: 16 }}>
        <button className={`btn btn-sm ${tab === 'earned' ? 'btn-primary' : 'btn-secondary'}`} onClick={() => setTab('earned')}><Coins size={14} /> Unpaid (by staff / month)</button>
        <button className={`btn btn-sm ${tab === 'payouts' ? 'btn-primary' : 'btn-secondary'}`} onClick={() => setTab('payouts')}><Wallet size={14} /> Payout History</button>
      </div>

      <div className="card"><div className="table-wrap">
        {loading ? <div className="empty-state"><RefreshCw size={24} className="spin" style={{ opacity: 0.4 }} /></div>
        : tab === 'earned' ? (
          earnedGroups.length === 0 ? <div className="empty-state"><Coins size={32} style={{ opacity: 0.3 }} /><p style={{ fontWeight: 600, marginTop: 8 }}>No unpaid staff commission</p></div>
          : <table>
              <thead><tr><th>Month</th><th>Staff</th><th style={{ textAlign: 'right' }}>Invoices</th><th style={{ textAlign: 'right' }}>Unpaid</th>{canPay && <th></th>}</tr></thead>
              <tbody>{earnedGroups.map((g, i) => (
                <tr key={i}>
                  <td>{monthKey(`${g.month}-01`)}</td>
                  <td><strong>{sName(g.staff_id)}</strong></td>
                  <td style={{ textAlign: 'right' }}>{g.count}</td>
                  <td style={{ textAlign: 'right', fontWeight: 700 }}>{money(g.total)}</td>
                  {canPay && <td><button className="btn btn-primary btn-sm" onClick={() => { setPayFor(g); setPayMethod(methods[0]?.id ?? ''); setPayRef(''); setPayErr(null); }}>Mark Paid</button></td>}
                </tr>))}
              </tbody>
            </table>
        ) : (
          payouts.length === 0 ? <div className="empty-state"><Wallet size={32} style={{ opacity: 0.3 }} /><p style={{ fontWeight: 600, marginTop: 8 }}>No payouts yet</p></div>
          : <table>
              <thead><tr><th>Paid On</th><th>Month</th><th>Staff</th><th style={{ textAlign: 'right' }}>Amount</th><th>Method</th><th>Reference</th></tr></thead>
              <tbody>{payouts.map(p => (
                <tr key={p.id}>
                  <td style={{ fontSize: 12.5 }}>{new Date(p.paid_at).toLocaleDateString()}</td>
                  <td>{monthKey(p.payout_month)}</td>
                  <td><strong>{sName(p.staff_id)}</strong></td>
                  <td style={{ textAlign: 'right', fontWeight: 700 }}>{money(Number(p.total_amount))}</td>
                  <td style={{ fontSize: 12.5 }}>{mName(p.payment_method_id)}</td>
                  <td style={{ fontSize: 12.5, color: 'var(--text-muted)' }}>{p.reference || '—'}</td>
                </tr>))}
              </tbody>
            </table>
        )}
      </div></div>

      {payFor && (
        <Modal title="Mark Staff Commission Paid" maxWidth={420} onClose={() => setPayFor(null)}
          footer={<><button className="btn btn-secondary" onClick={() => setPayFor(null)}>Cancel</button><button className="btn btn-primary" onClick={submitPay} disabled={payBusy}>{payBusy ? 'Processing…' : `Pay ${money(payFor.total)}`}</button></>}>
          <div className="form-grid">
            {payErr && <div className="alert alert-danger" style={{ marginBottom: 0 }}><span>⚠</span><div>{payErr}</div></div>}
            <div style={{ padding: 12, background: 'var(--surface-2)', borderRadius: 'var(--radius-sm)', fontSize: 13 }}>
              <strong>{sName(payFor.staff_id)}</strong> · {monthKey(`${payFor.month}-01`)}<br />
              Total unpaid: <strong>{money(payFor.total)}</strong>
            </div>
            <div className="form-group"><label>Payment Method</label>
              <select value={payMethod} onChange={e => setPayMethod(e.target.value)}>{methods.map(m => <option key={m.id} value={m.id}>{m.name}</option>)}</select>
            </div>
            <div className="form-group"><label>Reference</label><input value={payRef} onChange={e => setPayRef(e.target.value)} placeholder="Optional" /></div>
          </div>
        </Modal>
      )}

      {rateOpen && (
        <Modal title="Staff Commission Rate" maxWidth={380} onClose={() => setRateOpen(false)}
          footer={<><button className="btn btn-secondary" onClick={() => setRateOpen(false)}>Cancel</button><button className="btn btn-primary" onClick={saveRate} disabled={rateBusy}>{rateBusy ? 'Saving…' : 'Save'}</button></>}>
          <div className="form-grid">
            <div className="form-group"><label>Rate (% of each paid invoice, split equally)</label>
              <input type="number" min={0} step={0.1} value={rateDraft || ''} onChange={e => setRateDraft(+e.target.value)} autoFocus />
            </div>
            <div className="alert alert-info" style={{ marginBottom: 0 }}><span>ℹ️</span><div>Applies to invoices paid from now on. Already-earned commissions keep the rate they were calculated at.</div></div>
          </div>
        </Modal>
      )}
    </div>
  );
};

export default StaffCommissionsPage;
