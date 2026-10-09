import React, { useEffect, useState, useCallback, useMemo } from 'react';
import { CustomerSearchSelect } from '../components/SearchSelect';
import { supabase } from '../lib/supabase';
import { useAuth } from '../context/AuthContext';
import { isOwner, isOwnerOrManager } from '../types';
import { Modal } from '../components/ui';
import QRCodeCard, { publicAppUrl } from '../components/QRCodeCard';
import { RefreshCw, Search, Ban, PlayCircle, Users, QrCode, ShieldCheck, Edit3, XCircle, Trash2, CheckCircle2, Unlink, Gift } from 'lucide-react';
import DownlineModal from '../components/referrals/DownlineModal';
import ReferralPromotionPanel from '../components/referrals/ReferralPromotionPanel';
import { owedSplit } from '../lib/affiliatePayoutPresentation';

const money = (n: number) => `S$${Number(n ?? 0).toFixed(2)}`;
const d = (s?: string | null) => s ? new Date(s).toLocaleDateString('en-GB') : '—';

interface DirRow {
  customer_id: string; name: string; status: string; manually_suspended: boolean;
  referral_code: string | null; portal_account: 'not_claimed' | 'claimed' | 'disabled';
  direct_referrals: number; tier2: number; lifetime: number; unpaid: number; blocked: number; last_commission: string | null;
  /** 410: what the affiliate owes back (commission paid out and then taken
   *  back), recovered from their later commission. Absent before 410, when
   *  unpaid itself could be negative. */
  deduction?: number;
}
/** What a staff login may see: enough to identify an affiliate and hand over
 *  their link. Nothing about money, purchases, claims or accounts. */
interface StaffRow { customer_id: string; full_name: string; referral_code: string | null; status: string; link_usable: boolean; }

interface ClaimRow { claim_id: string; verified_email: string; entered_phone: string; entered_name?: string | null; candidate_customer_id: string | null; candidate_name: string | null; created_at: string; rejected_at?: string | null; rejection_reason?: string | null;
  /** 378: an Owner unlinked this login from a customer before (pending claims). */
  previously_unlinked?: boolean; unlinked_customer_ids?: string[];
  /** 378: an Owner unlinked a login (any) from the likely customer before. */
  suggested_customer_unlinked?: boolean;
  /** 379: an Owner or Manager rejected a claim that suggested the likely
   *  customer (pending and rejected claims). Its presence means 379 is on the
   *  server. */
  suggested_customer_rejected?: boolean;
  /** 378: a staff member rejected it, so staff may delete it (rejected claims). */
  rejected_by_staff?: boolean; }

/** affiliate_claim_link_check (378): whether this claim's login may be linked
 *  to the chosen customer by the person asking. resolve_affiliate_account_claim
 *  runs the same check, so 'problem' is exactly what Save would be refused with. */
interface LinkCheck {
  claim_id: string; entered_phone: string | null;
  customer_id: string; customer_name: string; customer_phone: string | null;
  phones_match: boolean; customer_deleted: boolean; customer_has_login: boolean; login_is_staff: boolean;
  previously_unlinked?: boolean; unlinked_at?: string | null; phone_changed_since_claim?: boolean;
  /** An Owner unlinked a login (this one or another) from the chosen customer. */
  customer_previously_unlinked?: boolean; customer_unlinked_at?: string | null;
  /** 379: an Owner or Manager rejected a claim that suggested the chosen customer (the latest, when). */
  customer_previously_rejected?: boolean; customer_rejected_at?: string | null;
  customers_sharing_phone?: number; suggested_customer?: boolean; own_claim?: boolean;
  /** An earlier claim of this login, deleted or rejected, suggested another customer (or none). */
  earlier_claim_other_customer?: boolean;
  any_customer: boolean; problem: string | null;
}

/** affiliate_portal_login (378, Owner only): the login linked to a customer,
 *  and the claims that linked it. */
interface PortalLogin {
  linked: boolean; login_email?: string | null; status?: string;
  /** last_sign_in_at is Supabase Auth's own record of the last sign-in. */
  linked_at?: string | null; last_sign_in_at?: string | null;
  claims?: { claim_id: string; entered_name: string | null; entered_phone: string | null; resolved_at: string | null;
             resolution_note: string | null; resolved_by_name: string | null }[];
}

// What staff are told when the chosen customer's phone is not the one the
// person entered at sign-up. The database refuses with the same words.
const STAFF_PHONE_RULE = 'Only an Owner or Manager can link this claim to a customer whose phone differs from the one entered.';
// The database refuses staff with these words when they delete a rejection an
// Owner or Manager made.
const STAFF_DELETE_RULE = 'Only an Owner or Manager can remove a rejection they made.';
// 379: after an Owner or Manager rejects a claim, the database refuses staff
// any login for the customer it suggested, with these words.
const CUSTOMER_REJECTED_RULE = 'An Owner or Manager rejected a claim for this customer. Only an Owner or Manager can link a login to them.';

/** The function is not on the server yet (PostgREST PGRST202): 378 has not
 *  been applied. An Owner or Manager then works exactly as before it. */
const missingFunction = (e: { code?: string; message?: string } | null | undefined) =>
  !!e && (e.code === 'PGRST202' || /Could not find the function/i.test(e.message ?? ''));
/** Before 378 the claim lists refuse staff with these words (or are missing):
 *  staff then see the page as it was before, without the claims and without
 *  an error. */
const claimsNotForStaffYet = (e: { code?: string; message?: string } | null | undefined) =>
  !!e && (missingFunction(e) || (e.message ?? '').trim() === 'Owner or Manager only');

const PORTAL: Record<string, { cls: string; label: string }> = {
  claimed: { cls: 'badge-success', label: 'Claimed' },
  not_claimed: { cls: 'badge-muted', label: 'Not Claimed' },
  disabled: { cls: 'badge-danger', label: 'Disabled' },
};

const AffiliatesPage: React.FC = () => {
  const { profile } = useAuth();
  const canManage = isOwnerOrManager(profile?.role);
  // Staff settle account claims too (378): they list, reject and delete them,
  // and Resolve only to the customer whose phone the person entered. Admin
  // and Inventory Manager keep the read-only directory alone, as before.
  const isStaff = profile?.role === 'staff';
  // The server does not offer staff the claims yet (378 not applied).
  const [claimsUnavailable, setClaimsUnavailable] = useState(false);
  const staffClaims = isStaff && !claimsUnavailable;
  const canHandleClaims = canManage || staffClaims;
  // Unlinking a portal login is the Owner's alone, not a Manager's.
  const canUnlink = isOwner(profile?.role);

  const [rows, setRows] = useState<DirRow[]>([]);
  // 398, Owner/Manager: the affiliates, or the referral promotion's report;
  // and one affiliate's downline with visits.
  const [view, setView] = useState<'affiliates' | 'promotion'>('affiliates');
  const [downlineFor, setDownlineFor] = useState<DirRow | null>(null);
  const [claims, setClaims] = useState<ClaimRow[]>([]);
  const [rejected, setRejected] = useState<ClaimRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [q, setQ] = useState('');
  const [busy, setBusy] = useState<string | null>(null);
  const [err, setErr] = useState<string | null>(null);
  const [success, setSuccess] = useState<string | null>(null);
  const [qrOpen, setQrOpen] = useState(false);
  // The affiliate whose referral link/QR is open. The code shown is the one
  // already on the row — the same one the portal shows the affiliate — so
  // opening this never creates or rotates anything.
  const [linkFor, setLinkFor] = useState<{ name: string; code: string | null; usable: boolean; status: string } | null>(null);

  // Staff directory: searched and paged on the server, because it is
  // company-wide and the API row limit would otherwise cut it off silently.
  const STAFF_PAGE = 50;
  const [staffRows, setStaffRows] = useState<StaffRow[]>([]);
  const [staffTotal, setStaffTotal] = useState(0);
  const [staffPage, setStaffPage] = useState(1);
  const [staffQ, setStaffQ] = useState('');
  const staffTicket = React.useRef(0);

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
  // 379: an Owner or Manager confirms a staff member's rejection, which then
  // protects the likely customer.
  const [protectFor, setProtectFor] = useState<ClaimRow | null>(null);
  const [protectReason, setProtectReason] = useState('');
  const [protectErr, setProtectErr] = useState<string | null>(null);
  // What the server says about linking the chosen customer: both phones, and
  // why it cannot be linked, if it cannot. Re-read whenever the choice changes.
  const [linkCheck, setLinkCheck] = useState<LinkCheck | null>(null);
  const [checking, setChecking] = useState(false);
  const [checkErr, setCheckErr] = useState<string | null>(null);
  const checkTicket = React.useRef(0);
  // Unlink-login modal (Owner)
  const [unlinkFor, setUnlinkFor] = useState<DirRow | null>(null);
  const [unlinkInfo, setUnlinkInfo] = useState<PortalLogin | null>(null);
  const [unlinkErr, setUnlinkErr] = useState<string | null>(null);
  const [unlinkReason, setUnlinkReason] = useState('');
  const [unlinkUnavailable, setUnlinkUnavailable] = useState(false);
  // Staff's claims load on their own, so the directory's own loading (which
  // clears the page error) cannot hide a failure here.
  const [claimsErr, setClaimsErr] = useState<string | null>(null);

  const loadStaffDirectory = useCallback(async (query: string, page: number) => {
    const ticket = ++staffTicket.current;
    setLoading(true); setErr(null);
    const { data, error } = await supabase.rpc('affiliate_staff_directory',
      { p_search: query.trim() || null, p_limit: STAFF_PAGE, p_offset: (page - 1) * STAFF_PAGE });
    if (ticket !== staffTicket.current) return;   // a newer search won
    setLoading(false);
    if (error) { setErr(error.message); return; }
    setStaffRows(((data as any)?.rows ?? []) as StaffRow[]);
    setStaffTotal(Number((data as any)?.total ?? 0));
  }, []);

  // Staff only: an Owner or Manager reads the claims in load(), as before.
  const loadClaims = useCallback(async () => {
    const [cl, rj] = await Promise.all([
      supabase.rpc('affiliate_pending_claims'),
      supabase.rpc('affiliate_rejected_claims'),
    ]);
    if (claimsNotForStaffYet(cl.error) || claimsNotForStaffYet(rj.error)) {
      setClaims([]); setRejected([]); setClaimsErr(null); setClaimsUnavailable(true);
      return;
    }
    setClaimsUnavailable(false);
    setClaims((cl.data as ClaimRow[]) ?? []);
    setRejected((rj.data as ClaimRow[]) ?? []);
    setClaimsErr(cl.error?.message ?? rj.error?.message ?? null);
  }, []);

  const load = useCallback(async () => {
    if (!canManage) { await loadStaffDirectory(staffQ, staffPage); return; }
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
  }, [canManage, loadStaffDirectory, staffQ, staffPage]);
  useEffect(() => { load(); }, [load]);
  // Staff's claims: once, then after each change and on Refresh; not on every
  // search or page of the directory.
  useEffect(() => { if (isStaff) void loadClaims(); }, [isStaff, loadClaims]);
  // Everything this login sees. For an Owner or Manager that is load().
  const reload = useCallback(async () => {
    await Promise.all([load(), isStaff ? loadClaims() : Promise.resolve()]);
  }, [load, isStaff, loadClaims]);
  // A request per keystroke would be one per letter of a name.
  useEffect(() => {
    if (canManage) return;
    const t = setTimeout(() => { setStaffPage(1); void loadStaffDirectory(staffQ, 1); }, 300);
    return () => clearTimeout(t);
  }, [staffQ, canManage, loadStaffDirectory]);

  const act = async (fn: string, args: any, key: string, okMsg?: string) => {
    setBusy(key); setErr(null); setSuccess(null);
    const { data, error } = await supabase.rpc(fn, args);
    setBusy(null);
    if (error) { setErr(error.message); return false; }
    // RPCs may return { ok:false, message } for safe no-ops (e.g. already resolved).
    if (data && typeof data === 'object' && (data as any).ok === false && (data as any).message) {
      // Staff: shown after the reload, whose directory read clears the page error.
      if (isStaff) { await reload(); setErr((data as any).message); return false; }
      setErr((data as any).message); await load(); return false;
    }
    if (okMsg) setSuccess(okMsg);
    await reload(); return true;
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

  useEffect(() => {
    const ticket = ++checkTicket.current;
    setLinkCheck(null); setCheckErr(null);
    if (!resolveFor || !resolveCust) { setChecking(false); return; }
    setChecking(true);
    void supabase.rpc('affiliate_claim_link_check', { p_claim_id: resolveFor.claim_id, p_customer_id: resolveCust })
      .then(({ data, error }) => {
        if (ticket !== checkTicket.current) return;   // a later choice won
        setChecking(false);
        // Before 378 is applied an Owner or Manager sees the window as it was.
        if (error) { if (!(canManage && missingFunction(error))) setCheckErr(error.message); return; }
        setLinkCheck(data as LinkCheck);
      });
  }, [resolveFor, resolveCust, canManage]);

  // Staff may link only the customer with the phone entered; anything the
  // server would refuse is refused here first. An Owner or Manager is never
  // held up by the check itself failing: Save then behaves as it always did.
  const staffPhoneDiffers = !canManage && !!linkCheck && !linkCheck.phones_match;
  // 379 is on the server when a pending row carries its flag. Until then a
  // rejection holds back only that one login, so the Reject window says
  // nothing about protecting the customer.
  const rejectProtects379 = typeof rejectFor?.suggested_customer_rejected === 'boolean';
  // The same for the Rejected list: its rows carry the flag once 379 is there.
  const rejectedProtects379 = rejected.some(r => typeof r.suggested_customer_rejected === 'boolean');
  const resolveBlocked = checking || !!linkCheck?.problem || staffPhoneDiffers
    || (!canManage && !!resolveCust && !linkCheck);

  const submitResolve = async () => {
    if (!resolveFor) return;
    if (resolveBlocked) return;
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

  const submitProtect = async () => {
    if (!protectFor || !protectReason.trim()) return;
    const name = protectFor.candidate_name ?? 'The likely customer';
    // Called directly rather than through act(): a refusal belongs in this
    // window, not on the page behind it.
    setBusy(protectFor.claim_id); setProtectErr(null); setErr(null); setSuccess(null);
    const { data, error } = await supabase.rpc('reject_affiliate_account_claim',
      { p_claim_id: protectFor.claim_id, p_reason: protectReason.trim() });
    setBusy(null);
    if (error) { setProtectErr(error.message); return; }
    // { ok:false, already:true }: not a staff member's rejection any more (an
    // Owner or Manager took it over first). The lists are read again.
    if (data && typeof data === 'object' && (data as any).ok === false) {
      setProtectErr((data as any).message ?? 'This claim could not be confirmed.');
      await reload(); return;
    }
    setProtectFor(null); setProtectReason('');
    setSuccess(`${name} is now protected: only an Owner or Manager can link a login to them.`);
    await reload();
  };

  const submitDelete = async () => {
    if (!deleteFor) return;
    const ok = await act('delete_affiliate_account_claim',
      { p_claim_id: deleteFor.claim_id }, deleteFor.claim_id, 'Account request deleted.');
    if (ok) setDeleteFor(null);
  };

  const openUnlink = async (r: DirRow) => {
    setUnlinkFor(r); setUnlinkInfo(null); setUnlinkErr(null); setUnlinkReason(''); setUnlinkUnavailable(false);
    const { data, error } = await supabase.rpc('affiliate_portal_login', { p_customer_id: r.customer_id });
    if (error) { if (missingFunction(error)) setUnlinkUnavailable(true); else setUnlinkErr(error.message); return; }
    setUnlinkInfo(data as PortalLogin);
  };

  const submitUnlink = async () => {
    if (!unlinkFor || !unlinkInfo?.linked) return;
    if (!unlinkReason.trim()) { setUnlinkErr('A reason is required to unlink a login.'); return; }
    const email = unlinkInfo.login_email ?? 'The login';
    const name = unlinkFor.name;
    // Called directly rather than through act(): a refusal belongs in this
    // window, not on the page behind it.
    setBusy(unlinkFor.customer_id); setUnlinkErr(null); setErr(null); setSuccess(null);
    const { error } = await supabase.rpc('unlink_affiliate_account',
      { p_customer_id: unlinkFor.customer_id, p_reason: unlinkReason.trim() });
    setBusy(null);
    if (error) { setUnlinkErr(error.message); return; }
    setUnlinkFor(null); setUnlinkInfo(null); setUnlinkReason('');
    setSuccess(`Login unlinked. ${email} no longer opens ${name}'s affiliate portal; their affiliate record, code and commissions are unchanged.`);
    await reload();
  };

  const activationUrl = `${publicAppUrl()}/affiliate/join`;
  // Reuses the portal's own link format; a code is never minted here.
  const referralUrl = (code: string) => `${publicAppUrl()}/r/${code}`;

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
            {canManage
              ? 'Customers register as affiliates through the Affiliate Signup QR/link. Owner/Manager can suspend or reactivate affiliate accounts.'
              : staffClaims
                ? 'Find an affiliate and hand over their referral link or QR code, or share the Affiliate Signup QR with someone who wants to join. You can settle account claims: link a login to the customer whose phone it entered, or reject or delete the request. Other changes to affiliate accounts are made by an Owner or Manager.'
                : 'Find an affiliate and hand over their referral link or QR code, or share the Affiliate Signup QR with someone who wants to join. Changes to affiliate accounts are made by an Owner or Manager.'}
          </p>
        </div>
        <div style={{ display: 'flex', gap: 8 }}>
          <button className="btn btn-secondary" onClick={reload} style={{ gap: 6 }}><RefreshCw size={15} /> Refresh</button>
          {/* The signup link is public; any staff member may hand it to someone
              who wants to join. It creates nothing by itself. */}
          <button className="btn btn-primary" onClick={() => setQrOpen(true)} style={{ gap: 6 }}><QrCode size={15} /> Affiliate Signup QR</button>
        </div>
      </div>

      {err && <div className="card" style={{ padding: 12, marginBottom: 12, borderColor: 'var(--danger)', color: 'var(--danger)', fontSize: 13.5 }}>{err}</div>}
      {claimsErr && <div className="card" data-error="claims" style={{ padding: 12, marginBottom: 12, borderColor: 'var(--danger)', color: 'var(--danger)', fontSize: 13.5 }}>Account claims could not be loaded: {claimsErr}</div>}
      {success && <div className="card" style={{ padding: 12, marginBottom: 12, borderColor: 'var(--success)', color: 'var(--success)', fontSize: 13.5, display: 'flex', gap: 8, alignItems: 'center' }}><CheckCircle2 size={16} /> {success}</div>}

      {/* Pending identity claims */}
      {canHandleClaims && claims.length > 0 && (
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
                      <td>{c.verified_email}<br /><small>{c.entered_name}</small>
                        {c.previously_unlinked && (
                          <span className="badge badge-danger" data-flag="previously-unlinked" style={{ marginLeft: 6 }}
                            title="An Owner unlinked this login from a customer before. Staff cannot link it back to that customer.">Previously unlinked</span>
                        )}
                      </td><td>{c.entered_phone}</td>
                      <td>{c.candidate_name ?? '—'}
                        {c.suggested_customer_unlinked && (
                          <span className="badge badge-danger" data-flag="customer-previously-unlinked" style={{ marginLeft: 6 }}
                            title="An Owner unlinked a login from this customer before. Only an Owner or Manager can link a login to them.">Login unlinked before</span>
                        )}
                        {c.suggested_customer_rejected && (
                          <span className="badge badge-danger" data-flag="customer-previously-rejected" style={{ marginLeft: 6 }}
                            title={CUSTOMER_REJECTED_RULE}>Claim rejected before</span>
                        )}
                      </td><td>{d(c.created_at)}</td>
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
      {canHandleClaims && rejected.length > 0 && (
        <div className="card" style={{ padding: 16, marginBottom: 16 }}>
          <h3 style={{ fontSize: 14, fontWeight: 600, marginBottom: 10, display: 'flex', gap: 8, alignItems: 'center' }}>
            <XCircle size={16} /> Rejected Account Claims ({rejected.length})
          </h3>
          <p style={{ fontSize: 12.5, color: 'var(--text-muted)', marginBottom: 10 }}>
            A rejected request blocks the person from auto-resubmitting. Delete it if you want them to be able to try again.
            {/* 379: said only once the server's rows show it is there. */}
            {rejectedProtects379 && (
              <span data-note="rejected-protects">
                {' A rejection by an Owner or Manager also protects the likely customer, even after it is deleted: only an Owner'
                  + ' or Manager can then link a login to them. A rejection by staff does not.'}
              </span>
            )}
          </p>
          <div style={{ overflow: 'auto' }}>
            <table className="table" style={{ width: '100%' }}>
              <thead><tr><th>Email</th><th>Phone</th><th>Likely Customer</th><th>Rejected</th><th>Reason</th><th></th></tr></thead>
              <tbody>
                {rejected.map(c => {
                  // Staff remove only a rejection a staff member made (378).
                  const notTheirs = isStaff && c.rejected_by_staff === false;
                  const name = c.candidate_name ?? 'the likely customer';
                  // 379: a staff member's rejection of a claim that suggested
                  // someone does not protect them; an Owner or Manager can
                  // confirm it so that it does.
                  const staffUnprotected = rejectedProtects379 && !!c.candidate_customer_id
                    && c.rejected_by_staff === true && c.suggested_customer_rejected === false;
                  return (
                  <tr key={c.claim_id}>
                    <td>{c.verified_email}<br /><small>{c.entered_name}</small></td><td>{c.entered_phone}</td>
                    <td>{c.candidate_name ?? '—'}
                      {rejectedProtects379 && c.candidate_customer_id && c.suggested_customer_rejected && (
                        <span className="badge badge-success" data-flag="customer-protected" style={{ marginLeft: 6 }}
                          title={CUSTOMER_REJECTED_RULE}>Protected</span>
                      )}
                      {staffUnprotected && (
                        <div data-note="staff-rejection" style={{ fontSize: 12, color: 'var(--text-muted)', marginTop: 4 }}>
                          {`Rejected by staff — does not protect ${name}`}
                        </div>
                      )}
                      {staffUnprotected && canManage && (
                        <button type="button" className="btn btn-secondary btn-sm" data-action="protect" style={{ marginTop: 6, gap: 4 }}
                          disabled={busy === c.claim_id} title={`Confirm this rejection as yours, so that it protects ${name}`}
                          onClick={() => { setProtectFor(c); setProtectReason(''); setProtectErr(null); }}>
                          <ShieldCheck size={13} /> {`Protect ${name}`}
                        </button>
                      )}
                    </td>
                    <td>{d(c.rejected_at)}
                      {/* 378: who rejected it (staff may delete only a staff member's). */}
                      {typeof c.rejected_by_staff === 'boolean' && (
                        <><br /><small data-rejected-by={c.rejected_by_staff ? 'staff' : 'owner-or-manager'}>
                          {c.rejected_by_staff ? 'by staff' : 'by an Owner or Manager'}
                        </small></>
                      )}
                    </td>
                    <td style={{ maxWidth: 220, whiteSpace: 'pre-line' }}>{c.rejection_reason ?? '—'}</td>
                    <td style={{ textAlign: 'right' }}>
                      <button className="btn btn-secondary btn-sm" disabled={busy === c.claim_id || notTheirs}
                        title={notTheirs ? STAFF_DELETE_RULE : 'Delete request'} onClick={() => setDeleteFor(c)}><Trash2 size={14} /> Delete</button>
                    </td>
                  </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        </div>
      )}

      {canManage && (
        <div style={{ display: 'flex', gap: 6, marginBottom: 12 }} role="tablist" aria-label="Affiliates view">
          <button type="button" role="tab" aria-selected={view === 'affiliates'} className={`btn btn-sm ${view === 'affiliates' ? 'btn-primary' : 'btn-secondary'}`}
            onClick={() => setView('affiliates')} style={{ gap: 4 }}><Users size={14} /> Affiliates</button>
          <button type="button" role="tab" aria-selected={view === 'promotion'} className={`btn btn-sm ${view === 'promotion' ? 'btn-primary' : 'btn-secondary'}`}
            onClick={() => setView('promotion')} style={{ gap: 4 }}><Gift size={14} /> Referral promotion</button>
        </div>
      )}

      {canManage && view === 'promotion' && <ReferralPromotionPanel isOwner={canUnlink} />}

      {(!canManage || view === 'affiliates') && <div style={{ position: 'relative', marginBottom: 12, maxWidth: 320 }}>
        <Search size={15} style={{ position: 'absolute', left: 10, top: 10, color: 'var(--text-muted)' }} />
        <input className="input" style={{ paddingLeft: 32 }} placeholder="Search name or code…" aria-label="Search affiliates"
          value={canManage ? q : staffQ} onChange={e => canManage ? setQ(e.target.value) : setStaffQ(e.target.value)} />
      </div>}

      {!canManage && (
        <div className="card" style={{ padding: 0, overflow: 'auto' }}>
          <table className="table" style={{ width: '100%' }}>
            <thead><tr><th>Affiliate</th><th>Status</th><th>Referral Code</th><th>Referral Link</th></tr></thead>
            <tbody>
              {loading && <tr><td colSpan={4} style={{ textAlign: 'center', padding: 20, color: 'var(--text-muted)' }}>Loading…</td></tr>}
              {!loading && staffRows.length === 0 && <tr><td colSpan={4} style={{ textAlign: 'center', padding: 20, color: 'var(--text-muted)' }}>No affiliates found</td></tr>}
              {staffRows.map(r => (
                <tr key={r.customer_id}>
                  <td style={{ fontWeight: 500 }}>{r.full_name}</td>
                  <td><span className={'badge ' + (r.link_usable ? 'badge-success' : 'badge-danger')}>{r.status === 'suspended' ? 'Suspended' : r.status === 'active' ? 'Active' : r.status}</span></td>
                  <td style={{ fontFamily: 'monospace', fontSize: 12.5 }}>{r.referral_code ?? '—'}</td>
                  <td>
                    <button type="button" className="btn btn-secondary btn-sm" style={{ gap: 4 }} disabled={!r.referral_code}
                      onClick={() => setLinkFor({ name: r.full_name, code: r.referral_code, usable: r.link_usable, status: r.status })}>
                      <QrCode size={14} /> QR &amp; link
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', padding: '8px 12px', fontSize: 12.5, color: 'var(--text-muted)', flexWrap: 'wrap', gap: 8 }}>
            <span>{staffTotal === 0 ? 'No affiliates' : `${(staffPage - 1) * STAFF_PAGE + 1}–${Math.min(staffPage * STAFF_PAGE, staffTotal)} of ${staffTotal}`}</span>
            <span style={{ display: 'flex', gap: 6 }}>
              <button type="button" className="btn btn-secondary btn-sm" disabled={staffPage <= 1} onClick={() => setStaffPage(p => p - 1)}>Previous</button>
              <button type="button" className="btn btn-secondary btn-sm" disabled={staffPage * STAFF_PAGE >= staffTotal} onClick={() => setStaffPage(p => p + 1)}>Next</button>
            </span>
          </div>
        </div>
      )}

      {canManage && view === 'affiliates' && <div className="card" style={{ padding: 0, overflow: 'auto' }}>
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
                  <td style={{ whiteSpace: 'nowrap' }}>
                    <span className={'badge ' + portal.cls}>{portal.label}</span>
                    {canUnlink && r.portal_account !== 'not_claimed' && (
                      <button type="button" className="btn btn-secondary btn-sm" style={{ marginLeft: 6, gap: 4 }}
                        title="Unlink the portal login from this customer" aria-label={`Unlink login of ${r.name}`}
                        disabled={busy === r.customer_id} onClick={() => void openUnlink(r)}>
                        <Unlink size={13} /> Unlink login
                      </button>
                    )}
                  </td>
                  <td style={{ fontFamily: 'monospace', fontSize: 12.5 }}>{r.referral_code ?? '—'}</td>
                  <td style={{ textAlign: 'right' }}>{r.direct_referrals}</td>
                  <td style={{ textAlign: 'right' }}>{r.tier2}</td>
                  <td style={{ textAlign: 'right' }}>{money(r.lifetime)}</td>
                  <td style={{ textAlign: 'right' }}>{money(owedSplit(r.unpaid).unpaid)}
                    {(r.deduction ?? owedSplit(r.unpaid).deduction) > 0 && <div style={{ fontSize: 11.5, color: 'var(--danger)' }} title="Commission already paid out was taken back; it is recovered from this affiliate's later commission before anything more is paid.">Owes {money(r.deduction ?? owedSplit(r.unpaid).deduction)} back</div>}</td>
                  <td style={{ textAlign: 'right' }}>{Number(r.blocked) > 0 ? money(r.blocked) : '—'}</td>
                  <td>{d(r.last_commission)}</td>
                  {canManage && (
                    <td style={{ textAlign: 'right', whiteSpace: 'nowrap' }}>
                      <button className="btn btn-secondary btn-sm" title="Referral QR and link" disabled={!r.referral_code} style={{ marginRight: 6 }}
                        onClick={() => setLinkFor({ name: r.name, code: r.referral_code, usable: !suspended && r.status === 'active', status: suspended ? 'suspended' : r.status })}><QrCode size={14} /></button>
                      <button className="btn btn-secondary btn-sm" title="Downline: Tier 1 and Tier 2, with visits" aria-label={`Downline of ${r.name}`}
                        onClick={() => setDownlineFor(r)} style={{ marginRight: 6 }}><Users size={14} /></button>
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
      </div>}

      {/* One affiliate's referral link and QR. Shown for suspended affiliates
          too, with the state made plain: a link that registers nobody is still
          the right answer to "what is their link". */}
      {linkFor && (
        <Modal title={`Referral link — ${linkFor.name}`} onClose={() => setLinkFor(null)}>
          {!linkFor.usable && (
            <div className="alert alert-danger" style={{ marginBottom: 12 }}>
              This affiliate is {linkFor.status === 'suspended' ? 'suspended' : linkFor.status}. Their link will not register new referrals until an Owner or Manager changes that.
            </div>
          )}
          {linkFor.code
            ? <div style={{ display: 'flex', justifyContent: 'center' }}>
                <QRCodeCard url={referralUrl(linkFor.code)} title="Referral link" filename={`energia-referral-${linkFor.code}`} />
              </div>
            : <p>This affiliate has no referral code.</p>}
        </Modal>
      )}

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
          {!canManage && (
            <p style={{ fontSize: 13, color: 'var(--text-secondary)', marginBottom: 14 }}>
              Staff can link only the customer whose phone is the one the person entered.
            </p>
          )}
          <p>Name entered: <strong>{resolveFor.entered_name ?? 'Not recorded'}</strong></p>
          {/* An Owner unlinked this login before: from the chosen customer
              (the server's check says so), or from another one. */}
          {(linkCheck?.previously_unlinked || resolveFor.previously_unlinked) && (
            <div className="alert alert-warning" data-flag="previously-unlinked" style={{ margin: '10px 0 12px' }}>
              <b>Previously unlinked.</b>{' '}
              {linkCheck?.previously_unlinked
                ? `An Owner unlinked this login from this customer${linkCheck.unlinked_at ? ` on ${d(linkCheck.unlinked_at)}` : ''}.`
                : 'An Owner unlinked this login from a customer before.'}
              {canManage && ' Staff cannot link it back to that customer; link it only once you are sure who the person is.'}
            </div>
          )}
          {/* An Owner unlinked another login from the chosen customer: staff
              cannot link any login to them. */}
          {linkCheck?.customer_previously_unlinked && !linkCheck.previously_unlinked && !checking && (
            <div className="alert alert-warning" data-flag="customer-previously-unlinked" style={{ margin: '10px 0 12px' }}>
              <b>Login unlinked before.</b>{' '}
              {`An Owner unlinked a login from this customer${linkCheck.customer_unlinked_at ? ` on ${d(linkCheck.customer_unlinked_at)}` : ''}.`}
              {canManage && ' Staff cannot link any login to them; link this one only once you are sure who the person is.'}
            </div>
          )}
          {/* 379: an Owner or Manager rejected a claim that suggested the chosen
              customer: staff cannot link any login to them. */}
          {linkCheck?.customer_previously_rejected && !checking && (
            <div className="alert alert-warning" data-flag="customer-previously-rejected" style={{ margin: '10px 0 12px' }}>
              <b>Claim rejected before.</b>{' '}
              {`An Owner or Manager rejected a claim for this customer${linkCheck.customer_rejected_at ? ` on ${d(linkCheck.customer_rejected_at)}` : ''}.`}
              {canManage && ' Staff cannot link any login to them; link this one only once you are sure who the person is.'}
            </div>
          )}
          <label style={{ display: 'block', fontSize: 13, fontWeight: 600, marginBottom: 6 }}>Customer to link</label>
          <div style={{ marginBottom: 12 }}><CustomerSearchSelect value={resolveCust} onChange={setResolveCust} /></div>
          {/* The two phones side by side: what the person typed at sign-up, and
              what is on the chosen customer's record. */}
          <div className="affiliate-phone-compare" style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(160px, 1fr))', gap: 10, marginBottom: 12 }}>
            <div className="card" style={{ padding: 10 }} data-phone="entered">
              <div style={{ fontSize: 12, color: 'var(--text-muted)' }}>Phone entered at sign-up</div>
              <div style={{ fontWeight: 600 }}>{resolveFor.entered_phone || 'None entered'}</div>
            </div>
            <div className="card" style={{ padding: 10 }} data-phone="customer">
              <div style={{ fontSize: 12, color: 'var(--text-muted)' }}>Customer's phone</div>
              <div style={{ fontWeight: 600 }}>
                {!resolveCust ? 'Choose a customer' : checking ? 'Checking…' : linkCheck ? (linkCheck.customer_phone || 'No phone on record') : '—'}
              </div>
            </div>
          </div>
          {linkCheck && !checking && linkCheck.phones_match && (
            <div className="alert alert-info" style={{ marginBottom: 12 }}>The phones match.</div>
          )}
          {linkCheck && !checking && !linkCheck.phones_match && canManage && (
            <div className="alert alert-warning" style={{ marginBottom: 12 }}>
              The phones differ. As an Owner or Manager you can still link this customer once you have verified who the person is.
            </div>
          )}
          {staffPhoneDiffers && !checking && (
            <div className="alert alert-danger" role="alert" style={{ marginBottom: 12 }}>{STAFF_PHONE_RULE}</div>
          )}
          {linkCheck?.problem && linkCheck.problem !== STAFF_PHONE_RULE && !checking && (
            <div className="alert alert-danger" role="alert" style={{ marginBottom: 12 }}>{linkCheck.problem}</div>
          )}
          {checkErr && <div className="alert alert-danger" role="alert" style={{ marginBottom: 12 }}>{checkErr}</div>}
          <label style={{ display: 'block', fontSize: 13, fontWeight: 600, marginBottom: 6 }}>Verification note (required)</label>
          <textarea className="input" rows={3} value={resolveNote} onChange={e => setResolveNote(e.target.value)} style={{ marginBottom: 14 }} />
          <div style={{ display: 'flex', gap: 8, justifyContent: 'flex-end' }}>
            <button className="btn btn-secondary" onClick={() => setResolveFor(null)}>Cancel</button>
            <button className="btn btn-primary" disabled={busy === resolveFor.claim_id || resolveBlocked} onClick={submitResolve}>Link Account</button>
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
          {/* 379: an Owner's or Manager's rejection protects the likely customer,
              as an Owner's Unlink does; a staff member's does not (staff are
              told so, unless the customer is protected already). */}
          {rejectProtects379 && canManage && rejectFor.candidate_customer_id && (
            <p data-note="reject-protects" style={{ fontSize: 13, color: 'var(--text-secondary)', marginBottom: 12, lineHeight: 1.6 }}>
              {`Rejecting also protects ${rejectFor.candidate_name ?? 'the likely customer'}: afterwards staff cannot link any login to them, `
                + 'and sign-up no longer links one to them automatically; only an Owner or Manager can. '
                + 'This stays even if the rejected request is deleted later.'}
            </p>
          )}
          {rejectProtects379 && canManage && !rejectFor.candidate_customer_id && (
            <p data-note="reject-protects" style={{ fontSize: 13, color: 'var(--text-secondary)', marginBottom: 12, lineHeight: 1.6 }}>
              No likely customer is suggested, so rejecting this claim does not protect any customer.
            </p>
          )}
          {rejectProtects379 && !canManage && rejectFor.candidate_customer_id
            && !rejectFor.suggested_customer_rejected && !rejectFor.suggested_customer_unlinked && (
            <p data-note="reject-staff" style={{ fontSize: 13, color: 'var(--text-secondary)', marginBottom: 12, lineHeight: 1.6 }}>
              {`Your rejection does not protect ${rejectFor.candidate_name ?? 'the likely customer'}: staff can still link another login to them, `
                + 'and sign-up can still link one automatically. If they need protecting, ask an Owner or Manager to reject this claim instead, '
                + 'or to protect them from Rejected Account Claims once you have rejected it.'}
            </p>
          )}
          <label style={{ display: 'block', fontSize: 13, fontWeight: 600, marginBottom: 6 }}>Reason for rejection (required)</label>
          <textarea className="input" rows={3} value={rejectReason} onChange={e => setRejectReason(e.target.value)} style={{ marginBottom: 14 }} />
          <div style={{ display: 'flex', gap: 8, justifyContent: 'flex-end' }}>
            <button className="btn btn-secondary" onClick={() => setRejectFor(null)}>Cancel</button>
            <button className="btn btn-primary" disabled={busy === rejectFor.claim_id} onClick={submitReject} style={{ gap: 4 }}><XCircle size={15} /> Reject Claim</button>
          </div>
        </Modal>
      )}

      {/* Unlink a portal login (Owner) */}
      {unlinkFor && (
        <Modal title={`Unlink portal login — ${unlinkFor.name}`} onClose={() => setUnlinkFor(null)} confirmClose={!!unlinkReason.trim()}>
          {!unlinkInfo && !unlinkErr && !unlinkUnavailable && <p style={{ fontSize: 13.5, color: 'var(--text-muted)' }}>Loading…</p>}
          {unlinkUnavailable && <p style={{ fontSize: 13.5 }}>Unlinking a login is not available yet. Nothing has been changed.</p>}
          {unlinkInfo && !unlinkInfo.linked && <p style={{ fontSize: 13.5 }}>This customer has no portal login linked.</p>}
          {unlinkInfo?.linked && (
            <div style={{ fontSize: 13, color: 'var(--text-secondary)', marginBottom: 12, lineHeight: 1.6 }}>
              <div><b>Login:</b> {unlinkInfo.login_email ?? '—'}</div>
              <div><b>Linked:</b> {d(unlinkInfo.linked_at)}{unlinkInfo.last_sign_in_at ? ` · last signed in ${d(unlinkInfo.last_sign_in_at)}` : ''}</div>
              {(unlinkInfo.claims ?? []).length > 0
                ? (unlinkInfo.claims ?? []).map(c => (
                    <div key={c.claim_id}>
                      <b>How:</b> account claim resolved by {c.resolved_by_name ?? 'someone'} on {d(c.resolved_at)}
                      {c.entered_phone ? ` (phone entered ${c.entered_phone})` : ''}{c.resolution_note ? ` — “${c.resolution_note}”` : ''}
                    </div>))
                : <div><b>How:</b> at sign-up, without a claim (the verified email, phone and name matched this customer).</div>}
            </div>
          )}
          {unlinkInfo?.linked && (
            <>
              <p style={{ fontSize: 13, color: 'var(--text-secondary)', marginBottom: 12, lineHeight: 1.6 }}>
                Unlinking removes only the link between this login and {unlinkFor.name}, so the customer can be linked again.
                Their affiliate record, referral code and link, referred customers, commissions and payouts stay as they are,
                and the claim history is kept. The person can still sign in, but no longer sees this customer's portal: they are
                asked to finish setting up again, which usually parks a new account claim and never links them back
                to {unlinkFor.name} by itself, even if their email, phone and name all match this customer's record.
              </p>
              <p data-note="after-unlink" style={{ fontSize: 13, color: 'var(--text-secondary)', marginBottom: 12, lineHeight: 1.6 }}>
                Afterwards staff cannot link any login to {unlinkFor.name}, this one or a new one, and sign-up no longer links
                one to them automatically; only an Owner or Manager can link a login to them.
                A new claim from this login shows as “Previously unlinked”, and a claim that suggests {unlinkFor.name} shows
                “Login unlinked before”. If the person must not get back in, Reject that claim.
              </p>
              <p data-note="other-customers" style={{ fontSize: 12.5, color: 'var(--text-muted)', marginBottom: 12, lineHeight: 1.6 }}>
                This covers {unlinkFor.name} only. For other customers, staff who change a customer's email, name or phone can
                still change which customer a sign-up is linked to automatically, as before.
              </p>
              <label style={{ display: 'block', fontSize: 13, fontWeight: 600, marginBottom: 6 }} htmlFor="unlink-reason">Reason (required)</label>
              <textarea id="unlink-reason" className="input" rows={3} value={unlinkReason} onChange={e => setUnlinkReason(e.target.value)} style={{ marginBottom: 14 }} />
            </>
          )}
          {unlinkErr && <div className="alert alert-danger" role="alert" style={{ marginBottom: 12 }}>{unlinkErr}</div>}
          <div style={{ display: 'flex', gap: 8, justifyContent: 'flex-end' }}>
            <button className="btn btn-secondary" onClick={() => setUnlinkFor(null)}>Cancel</button>
            <button className="btn btn-primary" disabled={!unlinkInfo?.linked || !unlinkReason.trim() || busy === unlinkFor.customer_id}
              onClick={submitUnlink} style={{ gap: 4 }}><Unlink size={15} /> Unlink login</button>
          </div>
        </Modal>
      )}

      {/* 379: an Owner or Manager confirms a staff member's rejection, which
          then protects the likely customer. */}
      {protectFor && (
        <Modal title={`Protect ${protectFor.candidate_name ?? 'the likely customer'}`} onClose={() => setProtectFor(null)}
          confirmClose={!!protectReason.trim()}>
          <div style={{ fontSize: 13, color: 'var(--text-secondary)', marginBottom: 12, lineHeight: 1.6 }}>
            <div><b>Email:</b> {protectFor.verified_email}</div>
            <div><b>Phone:</b> {protectFor.entered_phone}</div>
            <div><b>Rejected:</b> {d(protectFor.rejected_at)} by staff{protectFor.rejection_reason ? ` — “${protectFor.rejection_reason}”` : ''}</div>
          </div>
          <p data-note="protect-explains" style={{ fontSize: 13, color: 'var(--text-secondary)', marginBottom: 12, lineHeight: 1.6 }}>
            {`A member of staff rejected this claim, and a rejection by staff does not protect ${protectFor.candidate_name ?? 'the likely customer'}. `
              + `Confirming it as an Owner or Manager does: afterwards staff cannot link any login to ${protectFor.candidate_name ?? 'them'}, `
              + 'and sign-up no longer links one to them automatically; only an Owner or Manager can. This stays even if the request is deleted later.'}
          </p>
          <p data-note="protect-yours" style={{ fontSize: 12.5, color: 'var(--text-muted)', marginBottom: 12, lineHeight: 1.6 }}>
            The rejection becomes yours, so staff can no longer delete it. The staff member's reason stays, and yours is added below it unless it says the same.
          </p>
          <label style={{ display: 'block', fontSize: 13, fontWeight: 600, marginBottom: 6 }} htmlFor="protect-reason">Reason (required)</label>
          <textarea id="protect-reason" className="input" rows={3} value={protectReason} onChange={e => setProtectReason(e.target.value)} style={{ marginBottom: 14 }} />
          {protectErr && <div className="alert alert-danger" role="alert" style={{ marginBottom: 12 }}>{protectErr}</div>}
          <div style={{ display: 'flex', gap: 8, justifyContent: 'flex-end' }}>
            <button className="btn btn-secondary" onClick={() => setProtectFor(null)}>Cancel</button>
            <button className="btn btn-primary" disabled={!protectReason.trim() || busy === protectFor.claim_id} onClick={submitProtect} style={{ gap: 4 }}>
              <ShieldCheck size={15} /> {`Protect ${protectFor.candidate_name ?? 'the likely customer'}`}
            </button>
          </div>
        </Modal>
      )}

      {downlineFor && <DownlineModal customerId={downlineFor.customer_id} name={downlineFor.name} onClose={() => setDownlineFor(null)} />}

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
