import React, { useEffect, useState, useCallback, useMemo } from 'react';
import { CustomerSearchSelect } from '../components/SearchSelect';
import { supabase } from '../lib/supabase';
import { useAuth } from '../context/AuthContext';
import { isOwnerOrManager } from '../types';
import { Modal } from '../components/ui';
import QRCodeCard, { publicAppUrl } from '../components/QRCodeCard';
import { RefreshCw, Search, Ban, PlayCircle, Users, QrCode, ShieldCheck, Edit3, XCircle, Trash2, CheckCircle2 } from 'lucide-react';

const money = (n: number) => `S$${Number(n ?? 0).toFixed(2)}`;
const d = (s?: string | null) => s ? new Date(s).toLocaleDateString('en-GB') : '—';

interface DirRow {
  customer_id: string; name: string; status: string; manually_suspended: boolean;
  referral_code: string | null; portal_account: 'not_claimed' | 'claimed' | 'disabled';
  direct_referrals: number; tier2: number; lifetime: number; unpaid: number; blocked: number; last_commission: string | null;
}
interface ClaimRow { claim_id: string; verified_email: string; entered_phone: string; candidate_customer_id: string | null; candidate_name: string | null; created_at: string; rejected_at?: string | null; rejection_reason?: string | null; }

const PORTAL: Record<string, { cls: string; label: string }> = {
  claimed: { cls: 'badge-success', label: 'Claimed' },
  not_claimed: { cls: 'badge-muted', label: 'Not Claimed' },
  disabled: { cls: 'badge-danger', label: 'Disabled' },
};

const AffiliatesPage: React.FC = () => {
  const { profile } = useAuth();
  const canManage = isOwnerOrManager(profile?.role);

  const [rows, setRows] = useState<DirRow[]>([]);
  const [claims, setClaims] = useState<ClaimRow[]>([]);
  const [rejected, setRejected] = useState<ClaimRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [q, setQ] = useState('');
  const [busy, setBusy] = useState<string | null>(null);
  const [err, setErr] = useState<string | null>(null);
  const [success, setSuccess] = useState<string | null>(null);
  const [qrOpen, setQrOpen] = useState(false);

  // Correct-referrer modal
  const [fixFor, setFixFor] = useState<DirRow | null>(null);
  const [fixRef, setFixRef] = useState(''); const [fixReason, setFixReason] = useState('');
  // Resolve-claim modal
  const [resolveFor, setResolveFor] = useState<ClaimRow | null>(null);
  const [resolveCust, setResolveCust] = useState(''); const [resolveNote, setResolveNote] = useState('');
  // Reject-claim modal
  const [rejectFor, setRejectFor] = useState<ClaimRow | null>(null);
  const [rejectReason, setRejectReason] = useState('');
  // Delete-claim confirmation
  const [deleteFor, setDeleteFor] = useState<ClaimRow | null>(null);

  const load = useCallback(async () => {
    setLoading(true); setErr(null);
    const [dir, cl, rj] = await Promise.all([
      supabase.rpc('affiliate_admin_directory'),
      supabase.rpc('affiliate_pending_claims'),
      supabase.rpc('affiliate_rejected_claims'),
    ]);
    if (dir.error) setErr(dir.error.message);
    setRows((dir.data as DirRow[]) ?? []);
    setClaims((cl.data as ClaimRow[]) ?? []);
    setRejected((rj.data as ClaimRow[]) ?? []);
    setLoading(false);
  }, []);
  useEffect(() => { load(); }, [load]);

  const act = async (fn: string, args: any, key: string, okMsg?: string) => {
    setBusy(key); setErr(null); setSuccess(null);
    const { data, error } = await supabase.rpc(fn, args);
    setBusy(null);
    if (error) { setErr(error.message); return false; }
    // RPCs may return { ok:false, message } for safe no-ops (e.g. already resolved).
    if (data && typeof data === 'object' && (data as any).ok === false && (data as any).message) {
      setErr((data as any).message); await load(); return false;
    }
    if (okMsg) setSuccess(okMsg);
    await load(); return true;
  };

  const suspend = (r: DirRow) => {
    const reason = window.prompt(`Suspend ${r.name}? Enter a reason:`);
    if (reason == null) return;
    act('suspend_affiliate', { p_customer_id: r.customer_id, p_reason: reason || 'Suspended' }, r.customer_id, 'Affiliate suspended.');
  };
  const reactivate = (r: DirRow) => act('reactivate_affiliate', { p_customer_id: r.customer_id }, r.customer_id, 'Affiliate reactivated.');

  const submitFix = async () => {
    if (!fixFor) return;
    if (!fixReason.trim()) { setErr('A reason is required to correct a referrer.'); return; }
    const ok = await act('reassign_customer_referrer',
      { p_customer_id: fixFor.customer_id, p_new_referrer_id: fixRef || null, p_reason: fixReason.trim() }, fixFor.customer_id, 'Referrer updated successfully.');
    if (ok) { setFixFor(null); setFixRef(''); setFixReason(''); }
  };

  const submitResolve = async () => {
    if (!resolveFor) return;
    if (!resolveCust) { setErr('Choose the customer to link.'); return; }
    if (!resolveNote.trim()) { setErr('A verification note is required.'); return; }
    const ok = await act('resolve_affiliate_account_claim',
      { p_claim_id: resolveFor.claim_id, p_customer_id: resolveCust, p_note: resolveNote.trim() }, resolveFor.claim_id, 'Account claim resolved.');
    if (ok) { setResolveFor(null); setResolveCust(''); setResolveNote(''); }
  };

  const submitReject = async () => {
    if (!rejectFor) return;
    if (!rejectReason.trim()) { setErr('A reason for rejection is required.'); return; }
    const ok = await act('reject_affiliate_account_claim',
      { p_claim_id: rejectFor.claim_id, p_reason: rejectReason.trim() }, rejectFor.claim_id, 'Account claim rejected.');
    if (ok) { setRejectFor(null); setRejectReason(''); }
  };

  const submitDelete = async () => {
    if (!deleteFor) return;
    const ok = await act('delete_affiliate_account_claim',
      { p_claim_id: deleteFor.claim_id }, deleteFor.claim_id, 'Account request deleted.');
    if (ok) setDeleteFor(null);
  };

  const activationUrl = `${publicAppUrl()}/affiliate/join`;

  const filtered = useMemo(() => {
    const s = q.trim().toLowerCase();
    if (!s) return rows;
    return rows.filter(r => r.name.toLowerCase().includes(s) || (r.referral_code ?? '').toLowerCase().includes(s));
  }, [rows, q]);

  return (
    <div style={{ padding: 24 }}>
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', flexWrap: 'wrap', gap: 12, marginBottom: 8 }}>
        <div>
          <h1 style={{ fontSize: 22, fontWeight: 700 }}>Affiliates</h1>
          <p style={{ color: 'var(--text-secondary)', fontSize: 13.5, marginTop: 2 }}>
            Customers register as affiliates through the Affiliate Signup QR/link. Owner/Manager can suspend or reactivate affiliate accounts.
          </p>
        </div>
        <div style={{ display: 'flex', gap: 8 }}>
          <button className="btn btn-secondary" onClick={load} style={{ gap: 6 }}><RefreshCw size={15} /> Refresh</button>
          {canManage && <button className="btn btn-primary" onClick={() => setQrOpen(true)} style={{ gap: 6 }}><QrCode size={15} /> Affiliate Signup QR</button>}
        </div>
      </div>

      {err && <div className="card" style={{ padding: 12, marginBottom: 12, borderColor: 'var(--danger)', color: 'var(--danger)', fontSize: 13.5 }}>{err}</div>}
      {success && <div className="card" style={{ padding: 12, marginBottom: 12, borderColor: 'var(--success)', color: 'var(--success)', fontSize: 13.5, display: 'flex', gap: 8, alignItems: 'center' }}><CheckCircle2 size={16} /> {success}</div>}

      {/* Pending identity claims */}
      {canManage && claims.length > 0 && (
        <div className="card" style={{ padding: 16, marginBottom: 16, borderColor: 'var(--warning)' }}>
          <h3 style={{ fontSize: 14, fontWeight: 600, marginBottom: 10, display: 'flex', gap: 8, alignItems: 'center' }}>
            <ShieldCheck size={16} /> Pending Account Claims ({claims.length})
          </h3>
          <div style={{ overflow: 'auto' }}>
            <table className="table" style={{ width: '100%' }}>
              <thead><tr><th>Email</th><th>Phone</th><th>Likely Customer</th><th>When</th><th></th></tr></thead>
              <tbody>
                {claims.map(c => {
                  const running = busy === c.claim_id;
                  return (
                    <tr key={c.claim_id}>
                      <td>{c.verified_email}</td><td>{c.entered_phone}</td>
                      <td>{c.candidate_name ?? '—'}</td><td>{d(c.created_at)}</td>
                      <td style={{ textAlign: 'right', whiteSpace: 'nowrap' }}>
                        <button className="btn btn-secondary btn-sm" disabled={running} title="Resolve" onClick={() => { setResolveFor(c); setResolveCust(c.candidate_customer_id ?? ''); setResolveNote(''); }} style={{ marginRight: 6, gap: 4 }}><ShieldCheck size={14} /> Resolve</button>
                        <button className="btn btn-secondary btn-sm" disabled={running} title="Reject" onClick={() => { setRejectFor(c); setRejectReason(''); }} style={{ marginRight: 6, gap: 4 }}><XCircle size={14} /> Reject</button>
                        <button className="btn btn-secondary btn-sm" disabled={running} title="Delete request" onClick={() => setDeleteFor(c)}><Trash2 size={14} /></button>
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        </div>
      )}

      {/* Rejected identity claims (block automatic resubmission until deleted) */}
      {canManage && rejected.length > 0 && (
        <div className="card" style={{ padding: 16, marginBottom: 16 }}>
          <h3 style={{ fontSize: 14, fontWeight: 600, marginBottom: 10, display: 'flex', gap: 8, alignItems: 'center' }}>
            <XCircle size={16} /> Rejected Account Claims ({rejected.length})
          </h3>
          <p style={{ fontSize: 12.5, color: 'var(--text-muted)', marginBottom: 10 }}>
            A rejected request blocks the person from auto-resubmitting. Delete it if you want them to be able to try again.
          </p>
          <div style={{ overflow: 'auto' }}>
            <table className="table" style={{ width: '100%' }}>
              <thead><tr><th>Email</th><th>Phone</th><th>Likely Customer</th><th>Rejected</th><th>Reason</th><th></th></tr></thead>
              <tbody>
                {rejected.map(c => (
                  <tr key={c.claim_id}>
                    <td>{c.verified_email}</td><td>{c.entered_phone}</td>
                    <td>{c.candidate_name ?? '—'}</td><td>{d(c.rejected_at)}</td>
                    <td style={{ maxWidth: 220, whiteSpace: 'normal' }}>{c.rejection_reason ?? '—'}</td>
                    <td style={{ textAlign: 'right' }}>
                      <button className="btn btn-secondary btn-sm" disabled={busy === c.claim_id} title="Delete request" onClick={() => setDeleteFor(c)}><Trash2 size={14} /> Delete</button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}

      <div style={{ position: 'relative', marginBottom: 12, maxWidth: 320 }}>
        <Search size={15} style={{ position: 'absolute', left: 10, top: 10, color: 'var(--text-muted)' }} />
        <input className="input" style={{ paddingLeft: 32 }} placeholder="Search name or code…" value={q} onChange={e => setQ(e.target.value)} />
      </div>

      <div className="card" style={{ padding: 0, overflow: 'auto' }}>
        <table className="table" style={{ width: '100%' }}>
          <thead><tr>
            <th>Affiliate</th><th>Status</th><th>Portal Account</th><th>Referral Code</th>
            <th style={{ textAlign: 'right' }}>Direct</th><th style={{ textAlign: 'right' }}>Tier 2</th>
            <th style={{ textAlign: 'right' }}>Lifetime</th><th style={{ textAlign: 'right' }}>Unpaid</th><th style={{ textAlign: 'right' }}>Blocked</th>
            <th>Last Commission</th>{canManage && <th></th>}
          </tr></thead>
          <tbody>
            {loading && <tr><td colSpan={11} style={{ textAlign: 'center', padding: 20, color: 'var(--text-muted)' }}>Loading…</td></tr>}
            {!loading && filtered.length === 0 && <tr><td colSpan={11} style={{ textAlign: 'center', padding: 20, color: 'var(--text-muted)' }}>No affiliates found</td></tr>}
            {filtered.map(r => {
              const portal = PORTAL[r.portal_account] ?? PORTAL.not_claimed;
              const suspended = r.manually_suspended;
              return (
                <tr key={r.customer_id}>
                  <td style={{ fontWeight: 500 }}>{r.name}</td>
                  <td><span className={'badge ' + (suspended ? 'badge-danger' : 'badge-success')}>{suspended ? 'Suspended' : 'Active'}</span></td>
                  <td><span className={'badge ' + portal.cls}>{portal.label}</span></td>
                  <td style={{ fontFamily: 'monospace', fontSize: 12.5 }}>{r.referral_code ?? '—'}</td>
                  <td style={{ textAlign: 'right' }}>{r.direct_referrals}</td>
                  <td style={{ textAlign: 'right' }}>{r.tier2}</td>
                  <td style={{ textAlign: 'right' }}>{money(r.lifetime)}</td>
                  <td style={{ textAlign: 'right' }}>{money(r.unpaid)}</td>
                  <td style={{ textAlign: 'right' }}>{Number(r.blocked) > 0 ? money(r.blocked) : '—'}</td>
                  <td>{d(r.last_commission)}</td>
                  {canManage && (
                    <td style={{ textAlign: 'right', whiteSpace: 'nowrap' }}>
                      <button className="btn btn-secondary btn-sm" title="Correct referrer" onClick={() => { setFixFor(r); setFixRef(''); setFixReason(''); }} style={{ marginRight: 6 }}><Edit3 size={14} /></button>
                      {suspended
                        ? <button className="btn btn-secondary btn-sm" disabled={busy === r.customer_id} onClick={() => reactivate(r)} style={{ gap: 4 }}><PlayCircle size={14} /> Reactivate</button>
                        : <button className="btn btn-secondary btn-sm" disabled={busy === r.customer_id} onClick={() => suspend(r)} style={{ gap: 4 }}><Ban size={14} /> Suspend</button>}
                    </td>
                  )}
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>

      {/* Affiliate Activation QR */}
      {qrOpen && (
        <Modal title="Affiliate Registration" onClose={() => setQrOpen(false)}>
          <p style={{ fontSize: 13.5, color: 'var(--text-secondary)', marginBottom: 16 }}>
            Anyone who wants to become an Energia Affiliate can scan this QR (or open the link) and create their own account. New affiliates activate automatically after verifying their email.
          </p>
          <div style={{ display: 'flex', justifyContent: 'center' }}>
            <QRCodeCard url={activationUrl} title="Affiliate Signup Link" filename="energia-affiliate-activation" />
          </div>
        </Modal>
      )}

      {/* Correct Referrer */}
      {fixFor && (
        <Modal title={`Correct Referrer — ${fixFor.name}`} onClose={() => setFixFor(null)}>
          <p style={{ fontSize: 13, color: 'var(--text-secondary)', marginBottom: 14 }}>
            First valid referral wins, so referrers can only be changed here with a reason (this is audited). Leave the customer blank to clear the referrer.
          </p>
          <label style={{ display: 'block', fontSize: 13, fontWeight: 600, marginBottom: 6 }}>New Referrer (customer)</label>
          <div style={{ marginBottom: 12 }}><CustomerSearchSelect value={fixRef} onChange={setFixRef} /></div>
          <label style={{ display: 'block', fontSize: 13, fontWeight: 600, marginBottom: 6 }}>Reason (required)</label>
          <textarea className="input" rows={3} value={fixReason} onChange={e => setFixReason(e.target.value)} style={{ marginBottom: 14 }} />
          <div style={{ display: 'flex', gap: 8, justifyContent: 'flex-end' }}>
            <button className="btn btn-secondary" onClick={() => setFixFor(null)}>Cancel</button>
            <button className="btn btn-primary" disabled={busy === fixFor.customer_id} onClick={submitFix}>Save Correction</button>
          </div>
        </Modal>
      )}

      {/* Resolve Claim */}
      {resolveFor && (
        <Modal title="Resolve Affiliate Account" onClose={() => setResolveFor(null)}>
          <p style={{ fontSize: 13, color: 'var(--text-secondary)', marginBottom: 14 }}>
            After verifying identity, link this login ({resolveFor.verified_email}) to the correct existing customer. This does not change the customer's referrer or history.
          </p>
          <label style={{ display: 'block', fontSize: 13, fontWeight: 600, marginBottom: 6 }}>Customer to link</label>
          <div style={{ marginBottom: 12 }}><CustomerSearchSelect value={resolveCust} onChange={setResolveCust} /></div>
          <label style={{ display: 'block', fontSize: 13, fontWeight: 600, marginBottom: 6 }}>Verification note (required)</label>
          <textarea className="input" rows={3} value={resolveNote} onChange={e => setResolveNote(e.target.value)} style={{ marginBottom: 14 }} />
          <div style={{ display: 'flex', gap: 8, justifyContent: 'flex-end' }}>
            <button className="btn btn-secondary" onClick={() => setResolveFor(null)}>Cancel</button>
            <button className="btn btn-primary" disabled={busy === resolveFor.claim_id} onClick={submitResolve}>Link Account</button>
          </div>
        </Modal>
      )}

      {/* Reject Claim */}
      {rejectFor && (
        <Modal title="Reject Affiliate Account Claim" onClose={() => setRejectFor(null)}>
          <div style={{ fontSize: 13, color: 'var(--text-secondary)', marginBottom: 12, lineHeight: 1.6 }}>
            <div><b>Email:</b> {rejectFor.verified_email}</div>
            <div><b>Phone:</b> {rejectFor.entered_phone}</div>
            <div><b>Likely Customer:</b> {rejectFor.candidate_name ?? '—'}</div>
          </div>
          <label style={{ display: 'block', fontSize: 13, fontWeight: 600, marginBottom: 6 }}>Reason for rejection (required)</label>
          <textarea className="input" rows={3} value={rejectReason} onChange={e => setRejectReason(e.target.value)} style={{ marginBottom: 14 }} />
          <div style={{ display: 'flex', gap: 8, justifyContent: 'flex-end' }}>
            <button className="btn btn-secondary" onClick={() => setRejectFor(null)}>Cancel</button>
            <button className="btn btn-primary" disabled={busy === rejectFor.claim_id} onClick={submitReject} style={{ gap: 4 }}><XCircle size={15} /> Reject Claim</button>
          </div>
        </Modal>
      )}

      {/* Delete Claim confirmation */}
      {deleteFor && (
        <Modal title="Delete this Affiliate account request?" onClose={() => setDeleteFor(null)}>
          <p style={{ fontSize: 13.5, color: 'var(--text-secondary)', marginBottom: 16, lineHeight: 1.6 }}>
            This removes the account-linking request only. It does not delete the Customer or their Supabase login. They may submit a new request later.
          </p>
          <div style={{ display: 'flex', gap: 8, justifyContent: 'flex-end' }}>
            <button className="btn btn-secondary" onClick={() => setDeleteFor(null)}>Cancel</button>
            <button className="btn btn-primary" disabled={busy === deleteFor.claim_id} onClick={submitDelete} style={{ gap: 4 }}><Trash2 size={15} /> Delete Request</button>
          </div>
        </Modal>
      )}
    </div>
  );
};

export default AffiliatesPage;
