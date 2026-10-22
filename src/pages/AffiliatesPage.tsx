import React, { useEffect, useState, useCallback, useMemo } from 'react';
import { CustomerSearchSelect } from '../components/SearchSelect';
import { supabase } from '../lib/supabase';
import { useAuth } from '../context/AuthContext';
import { isOwner, isOwnerOrManager } from '../types';
import { Modal, ReasonModal } from '../components/ui';
import QRCodeCard, { publicAppUrl } from '../components/QRCodeCard';
import { RefreshCw, Search, Ban, PlayCircle, Users, QrCode, ShieldCheck, Edit3, XCircle, Trash2, CheckCircle2, Unlink, Gift, PhoneCall } from 'lucide-react';
import DownlineModal from '../components/referrals/DownlineModal';
import ReferralPromotionPanel from '../components/referrals/ReferralPromotionPanel';
import { owedSplit } from '../lib/affiliatePayoutPresentation';
import { canSeeCustomerProfile } from '../lib/customers/customerRoles.mjs';

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
/** 425: a customer made through a referral link with the phone of a customer
 *  already there, under another name. They count for a referral promotion
 *  once an Owner or Manager checks them as a different person (Q19 = A). */
interface SignupCheck {
  check_id: string; customer_id: string; customer_name: string; phone: string | null; customer_deleted?: boolean;
  referrer_customer_id: string | null; referrer_name: string | null; referral_code: string | null; signed_up_at: string;
  shares_with: { customer_id: string; name: string; deleted?: boolean; paid_invoices: number }[];
}
/** 437: an affiliate who signed up on a fresh customer record that may be a
 *  customer already there (the Owner, 20 Oct 2026, decision 6). An Owner or
 *  Manager links them (the fresh record joins the customer) or keeps them
 *  separate. The person who signed up is never told. */
interface SignupMatchCandidate {
  customer_id: string; name: string; phone: string | null; email: string | null; created_at: string;
  matched_by: ('phone' | 'email' | 'name')[]; has_login: boolean; protected: boolean;
  /** The customer's own affiliate record's code (an Owner unlinked the login
   *  that had it): linked, they keep it and the new record's is retired.
   *  Absent before this was added. */
  own_referral_code?: string | null;
  /** Linked to them, the new record's code is retired (they have an
   *  affiliate record of their own; AFF-SIGNUP-9 and -14). */
  retires_new_code?: boolean;
  /** What Link does with the email they signed up with (AFF-SIGNUP-12):
   *  copies it (the customer has none), the customer keeps their own, or it
   *  is left because another customer already has it. */
  email_on_link?: 'copy' | 'keep_own' | 'in_use' | 'none';
  /** The very same phone and a name of the same words, and an affiliate
   *  login of their own (AFF-SIGNUP-13). */
  twin?: boolean;
  /** AFF-SIGNUP-16: whether "Use the phone they signed up with" starts
   *  ticked, as the server works it out, and why: 'email_keep_own' and
   *  'email_in_use' (the email they signed up with cannot be copied),
   *  'waiting_seminar' and 'waiting_qr' (something of theirs waits under To
   *  match); 'same_phone' and 'no_signup_phone' when there is nothing to
   *  tick. Absent before this was added: unticked. */
  use_signup_phone_default?: boolean;
  use_signup_phone_why?: string[];
  /** Why this customer cannot be linked; null when they can. */
  problem: string | null;
}
interface SignupMatch {
  match_id: string; signed_up_at: string; reason: string;
  entered_name: string | null; entered_phone: string | null;
  customer_id: string; customer_name: string; phone: string | null; email: string | null; login_email: string | null;
  referral_code: string | null; referrals: number;
  /** AFF-SIGNUP-13: a customer with the very same phone and name already
   *  has an affiliate login (the first of them). */
  twin?: boolean; twin_customer_id?: string | null;
  /** AFF-SIGNUP-18: 'may_be_someone_else' for a login joined to a customer
   *  on the phone alone under another name (reason 'phone_other_name'):
   *  customer_* is the record it joined, entered_name the name typed, and
   *  there is no one to link. Otherwise (or absent) a fresh record. */
  kind?: 'fresh_record' | 'may_be_someone_else';
  /** AFF-SIGNUP-16: held under To match with the fresh record as a
   *  candidate: seminar registrations (null before 436) and QR forms. */
  waiting?: { seminar: number | null; qr: number } | null;
  candidates: SignupMatchCandidate[];
}
/** AFF-SIGNUP-17: commission Link earned on a paid invoice it moved. */
interface LinkCommission {
  invoice_id: string; invoice_no: string | null; dated?: string | null; amount?: number;
  rows?: { tier: string; referrer_name: string | null; amount: number; status: string; block_reason?: string | null }[];
  why?: 'none_due' | 'refused'; message?: string | null;
}
/** What Link answers (437; AFF-SIGNUP-12, -17): what it put on the customer,
 *  and the commission it earned on the paid invoices it moved. A replay (the
 *  same request id after a lost answer) answers the same, read back from the
 *  link's audit row, with replayed true. */
interface LinkAnswer {
  ok?: boolean; message?: string; replayed?: boolean; phone_refused?: boolean;
  email_copied?: string | null; phone_changed?: boolean; phone?: string | null; notes?: string[];
  commission_dated?: string | null; commission_earned?: LinkCommission[]; commission_not_earned?: LinkCommission[];
}
/** Two phones are the same number when their digits are. */
const samePhone = (a?: string | null, b?: string | null) =>
  !!a && !!b && a.replace(/\D/g, '') === b.replace(/\D/g, '');
/** AFF-SIGNUP-18: a login joined to a customer on the phone alone under
 *  another name, listed so staff check who it is. */
const isSomeoneElse = (m: SignupMatch) => m.kind === 'may_be_someone_else' || m.reason === 'phone_other_name';
/** AFF-SIGNUP-16: what of this sign-up waits under To match, or null. */
const waitingText = (m: SignupMatch) => {
  const seminar = m.waiting?.seminar ?? 0;
  const qr = m.waiting?.qr ?? 0;
  const parts = [seminar > 0 ? `${seminar} seminar ${seminar === 1 ? 'registration' : 'registrations'}` : null,
                 qr > 0 ? `${qr} QR health ${qr === 1 ? 'form' : 'forms'}` : null].filter(Boolean);
  return parts.length > 0 ? `Waiting under To match: ${parts.join(' and ')}.` : null;
};
/** AFF-SIGNUP-12: the tick box is offered only when the phone they signed
 *  up with is not the customer's already. */
const phoneBoxOffered = (match: SignupMatch, cand: SignupMatchCandidate) =>
  !!match.entered_phone && !samePhone(cand.phone, match.entered_phone);
/** Why a sign-up got a fresh record and is listed, in the page's words. */
const MATCH_REASON: Record<string, string> = {
  shared_phone: 'Several customers have this phone, and the name did not pick one of them.',
  phone_unconfirmed: 'A customer\'s stored number could be this phone (its country is not confirmed).',
  customer_has_login: 'The customer with this phone already has an affiliate login.',
  protected_customer: 'The customer with this phone is protected: an Owner unlinked a login from them, or an Owner or Manager rejected a claim for them.',
  affiliate_removed: 'The customer with this phone had their affiliate record removed.',
  email_match: 'A customer we already have uses the same email.',
  name_match: 'A customer we already have has a name with the same words.',
  earlier_claim: 'An earlier account claim of theirs suggested a customer.',
  phone_other_name: 'Joined the customer with this phone on the phone alone, but signed up under another name.',
};
/** AFF-SIGNUP-16: why the phone box starts ticked, in the page's words. */
const PHONE_WHY: Record<string, (name: string) => string> = {
  email_keep_own: name => `${name} keeps their own email, so the email they signed up with is not copied`,
  email_in_use: () => 'another customer already has the email they signed up with, so it is not copied',
};
/** AFF-SIGNUP-17: an invoice's commission, in the page's words. */
const TIER: Record<string, string> = { tier1: 'Tier 1', tier2: 'Tier 2' };
const commissionLine = (c: LinkCommission) => {
  const rows = (c.rows ?? []).map(r => `${TIER[r.tier] ?? r.tier} ${r.referrer_name ?? 'someone'} ${money(r.amount)}`
    + (r.status === 'blocked' ? ` (blocked${r.block_reason ? `: ${r.block_reason}` : ''})` : ''));
  return `${c.invoice_no ?? 'an invoice'}${rows.length ? `: ${rows.join(', ')}` : ''}`;
};
const MATCHED_BY: Record<string, string> = { phone: 'Phone', email: 'Email', name: 'Name' };

/** The affiliate's current referrer, read when Correct Referrer opens. */
interface CurrentReferrer { id: string | null; name: string | null; since: string | null }

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
  // 453 (the Owner, 22 Oct 2026): the Downline (Tier 1 and Tier 2, with
  // visits and its export) is also on the staff list, for Staff and Admins
  // (the roles that see a customer's full Profile); not Inventory Managers.
  const canDownline = canSeeCustomerProfile(profile?.role);

  const [rows, setRows] = useState<DirRow[]>([]);
  // 398, Owner/Manager: the affiliates, or the referral promotion's report;
  // and one affiliate's downline with visits (453: from the staff list too).
  const [view, setView] = useState<'affiliates' | 'promotion'>('affiliates');
  const [downlineFor, setDownlineFor] = useState<{ customer_id: string; name: string } | null>(null);
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
  // The search and page the directory on screen was loaded for. A Refresh
  // reads them, so it never needs the newest keystroke (AFFILIATES-10).
  const staffQRef = React.useRef('');
  const staffPageRef = React.useRef(1);
  const firstStaffSearch = React.useRef(true);

  // Correct-referrer modal
  const [fixFor, setFixFor] = useState<DirRow | null>(null);
  const [fixRef, setFixRef] = useState(''); const [fixReason, setFixReason] = useState('');
  // Who refers this affiliate now (null while it loads), and the tick that
  // removing them needs (AFFILIATES-8).
  const [fixCurrent, setFixCurrent] = useState<CurrentReferrer | null>(null);
  const [fixCurrentErr, setFixCurrentErr] = useState<string | null>(null);
  const [fixRemove, setFixRemove] = useState(false);
  const fixTicket = React.useRef(0);
  // Suspend asks for its reason in a window (AFFILIATES-8).
  const [suspendFor, setSuspendFor] = useState<DirRow | null>(null);
  // 425: sign-ups that share a customer's phone, and the one being checked.
  const [signupChecks, setSignupChecks] = useState<SignupCheck[]>([]);
  const [signupChecksErr, setSignupChecksErr] = useState<string | null>(null);
  const [decideFor, setDecideFor] = useState<{ check: SignupCheck; decision: 'different_person' | 'same_person' } | null>(null);
  const [decideNote, setDecideNote] = useState('');
  const [decideErr, setDecideErr] = useState<string | null>(null);
  // 437: affiliates on fresh records that may be a customer already there.
  const [matches, setMatches] = useState<SignupMatch[]>([]);
  const [matchesErr, setMatchesErr] = useState<string | null>(null);
  // The link being confirmed. Its request id is made when the window opens,
  // so a second press of Link (or a retry after a lost answer) is the same
  // link, and the server answers it as replayed.
  const [linkMatch, setLinkMatch] = useState<{ match: SignupMatch; cand: SignupMatchCandidate; requestId: string } | null>(null);
  const [linkNote, setLinkNote] = useState('');
  const [linkErr, setLinkErr] = useState<string | null>(null);
  // AFF-SIGNUP-12: "use the phone they signed up with". AFF-SIGNUP-16: it
  // starts as the server suggests (ticked when the email cannot be copied or
  // something of theirs waits under To match), and staff can change it.
  const [linkUsePhone, setLinkUsePhone] = useState(false);
  const [keepFor, setKeepFor] = useState<SignupMatch | null>(null);
  // AFF-SIGNUP-18: "Same person" for a phone-only join under another name.
  const [sameFor, setSameFor] = useState<SignupMatch | null>(null);
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
  // AFF-SIGNUP-18: the "May be someone else" entry the window was opened
  // from, so it says how that login was joined (the phone alone, under
  // another name). Null from the directory.
  const [unlinkFrom, setUnlinkFrom] = useState<SignupMatch | null>(null);
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
    if (!canManage) { await loadStaffDirectory(staffQRef.current, staffPageRef.current); return; }
    setLoading(true); setErr(null);
    const [dir, cl, rj, chk, mt] = await Promise.all([
      supabase.rpc('affiliate_admin_directory'),
      supabase.rpc('affiliate_pending_claims'),
      supabase.rpc('affiliate_rejected_claims'),
      supabase.rpc('referral_signup_checks_pending'),
      supabase.rpc('affiliate_signup_matches_open'),
    ]);
    // 437: before it is on the server there is no list and no error.
    setMatches(mt.error ? [] : ((mt.data as SignupMatch[]) ?? []));
    setMatchesErr(mt.error && !missingFunction(mt.error) ? mt.error.message : null);
    if (dir.error) setErr(dir.error.message);
    setRows((dir.data as DirRow[]) ?? []);
    setClaims((cl.data as ClaimRow[]) ?? []);
    setRejected((rj.data as ClaimRow[]) ?? []);
    // A failed claims list says so, rather than looking like there are none.
    setClaimsErr(cl.error?.message ?? rj.error?.message ?? null);
    // Before 425 the sign-up checks are not on the server: no list, no error.
    setSignupChecks(chk.error ? [] : ((chk.data as SignupCheck[]) ?? []));
    setSignupChecksErr(chk.error && !missingFunction(chk.error) ? chk.error.message : null);
    setLoading(false);
  }, [canManage, loadStaffDirectory]);
  // An Owner or Manager: everything at once. Staff: the directory loads from
  // the search box and the page buttons below, the claims on their own.
  useEffect(() => { if (canManage) void load(); }, [load, canManage]);
  // Staff's claims: once, then after each change and on Refresh; not on every
  // search or page of the directory.
  useEffect(() => { if (isStaff) void loadClaims(); }, [isStaff, loadClaims]);
  // Everything this login sees. For an Owner or Manager that is load().
  const reload = useCallback(async () => {
    await Promise.all([load(), isStaff ? loadClaims() : Promise.resolve()]);
  }, [load, isStaff, loadClaims]);
  // Staff's directory, one page. A new search starts at page 1.
  const loadStaffPage = useCallback((page: number) => {
    staffPageRef.current = page; setStaffPage(page);
    return loadStaffDirectory(staffQRef.current, page);
  }, [loadStaffDirectory]);
  // A request per keystroke would be one per letter of a name: the search
  // waits 300 ms after the last key. The first load does not wait.
  useEffect(() => {
    if (canManage) return;
    if (firstStaffSearch.current) { firstStaffSearch.current = false; staffQRef.current = staffQ; void loadStaffPage(1); return; }
    const t = setTimeout(() => { staffQRef.current = staffQ; void loadStaffPage(1); }, 300);
    return () => clearTimeout(t);
  }, [staffQ, canManage, loadStaffPage]);

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

  // The reason is required: the window refuses a blank one, and the server
  // too (no 'Suspended' stand-in any more).
  const submitSuspend = async (reason: string): Promise<string | null> => {
    if (!suspendFor) return null;
    const r = suspendFor;
    setBusy(r.customer_id); setErr(null); setSuccess(null);
    const { error } = await supabase.rpc('suspend_affiliate', { p_customer_id: r.customer_id, p_reason: reason.trim() });
    setBusy(null);
    if (error) return error.message;
    setSuccess(`${r.name} is suspended. Their link no longer registers new referrals.`);
    await reload();
    return null;
  };
  const reactivate = (r: DirRow) => act('reactivate_affiliate', { p_customer_id: r.customer_id }, r.customer_id, 'Affiliate reactivated.');

  // Correct Referrer: who refers this affiliate now, and since when.
  const openFix = async (r: DirRow) => {
    const ticket = ++fixTicket.current;
    setFixFor(r); setFixRef(''); setFixReason(''); setFixRemove(false); setFixCurrent(null); setFixCurrentErr(null);
    const { data, error } = await supabase.from('customers').select('referred_by, referred_at, created_at').eq('id', r.customer_id).maybeSingle();
    if (ticket !== fixTicket.current) return;
    if (error) { setFixCurrentErr(error.message); return; }
    const refId = (data as any)?.referred_by ?? null;
    let name: string | null = null;
    if (refId) {
      const n = await supabase.from('customers').select('full_name').eq('id', refId).maybeSingle();
      if (ticket !== fixTicket.current) return;
      if (n.error) { setFixCurrentErr(n.error.message); return; }
      name = (n.data as any)?.full_name ?? null;
    }
    setFixCurrent({ id: refId, name, since: refId ? ((data as any)?.referred_at ?? (data as any)?.created_at ?? null) : null });
  };
  const closeFix = () => { fixTicket.current++; setFixFor(null); };
  const fixRemoving = !!fixCurrent?.id && !fixRef;
  const fixUnchanged = !!fixCurrent && (fixRef || null) === (fixCurrent.id ?? null);
  const fixBlocked = !fixCurrent || fixUnchanged || !fixReason.trim() || (fixRemoving && !fixRemove);

  const submitFix = async () => {
    if (!fixFor || fixBlocked) return;
    const ok = await act('reassign_customer_referrer',
      { p_customer_id: fixFor.customer_id, p_new_referrer_id: fixRef || null, p_reason: fixReason.trim() }, fixFor.customer_id,
      fixRemoving ? 'Referrer removed.' : 'Referrer updated successfully.');
    if (ok) { setFixFor(null); setFixRef(''); setFixReason(''); setFixRemove(false); }
  };

  // 437: an Owner or Manager links an affiliate on a fresh record to the
  // customer already there. The fresh record joins that customer
  // (merge_customer_records): the login, the referral code and the referrals
  // made since move with it.
  const openLink = (match: SignupMatch, cand: SignupMatchCandidate) => {
    setLinkMatch({ match, cand, requestId: crypto.randomUUID() }); setLinkNote(''); setLinkErr(null);
    setLinkUsePhone(phoneBoxOffered(match, cand) && !!cand.use_signup_phone_default);
  };
  const submitLink = async () => {
    if (!linkMatch) return;
    const { match, cand, requestId } = linkMatch;
    // AFF-SIGNUP-12: offered only when the phone they signed up with is not
    // the customer's already.
    const usePhone = linkUsePhone && !!match.entered_phone && !samePhone(cand.phone, match.entered_phone);
    setBusy(match.match_id); setLinkErr(null); setErr(null); setSuccess(null);
    const { data, error } = await supabase.rpc('link_affiliate_signup',
      { p_match_id: match.match_id, p_customer_id: cand.customer_id, p_note: linkNote.trim() || null, p_request_id: requestId,
        p_use_signup_phone: usePhone });
    setBusy(null);
    if (error) { setLinkErr(error.message); return; }
    const answer = (data && typeof data === 'object' ? data : {}) as LinkAnswer;
    if (answer.ok === false) {
      // A phone the phone rule refuses changes nothing: the window stays,
      // and the server's words say to untick the box.
      setLinkErr(answer.message ?? 'This sign-up could not be linked.');
      await reload(); return;
    }
    setLinkMatch(null); setLinkNote(''); setLinkUsePhone(false);
    const done = [cand.own_referral_code
      ? `${match.customer_name} is linked to ${cand.name}. Their affiliate login now uses ${cand.name}'s own affiliate record and referral code ${cand.own_referral_code}.`
      : `${match.customer_name} is linked to ${cand.name}. Their affiliate login, referral code and referrals now belong to ${cand.name}.`];
    if (answer.phone_changed && answer.phone) done.push(`${cand.name}'s phone is now ${answer.phone}.`);
    if (answer.email_copied) done.push(`The email they signed up with, ${answer.email_copied}, is now on ${cand.name}.`);
    done.push(...(answer.notes ?? []));
    // AFF-SIGNUP-17: commission earned on the paid invoices moved, and any
    // that could not be earned.
    const earned = answer.commission_earned ?? [];
    if (earned.length > 0) {
      done.push(`Commission earned on the paid ${earned.length === 1 ? 'invoice' : 'invoices'} moved to ${cand.name}`
        + `${answer.commission_dated ? `, dated ${d(answer.commission_dated)}` : ''}: ${earned.map(commissionLine).join('; ')}.`);
    }
    const notEarned = answer.commission_not_earned ?? [];
    const noneDue = notEarned.filter(c => c.why !== 'refused');
    const refused = notEarned.filter(c => c.why === 'refused');
    if (noneDue.length > 0) {
      done.push(`No commission is due on ${noneDue.map(c => c.invoice_no ?? 'an invoice').join(', ')} by the commission rules`
        + ' (for example it names their own affiliate code, or no affiliate on purpose).');
    }
    if (refused.length > 0) {
      done.push(`Commission could not be earned on ${refused.map(c => `${c.invoice_no ?? 'an invoice'}${c.message ? ` (${c.message})` : ''}`).join(', ')}:`
        + ' the link is done; ask the Owner to check the commission on that invoice.');
    }
    // A press after a lost answer: the server did it the first time and
    // says what it did then (its audit row); nothing was linked or earned
    // again.
    if (answer.replayed) {
      done.splice(1, 0, done.length > 1
        ? 'This link had already gone through on an earlier press; nothing was linked, changed or earned again. What it did then:'
        : 'This link had already gone through on an earlier press; nothing was linked, changed or earned again.');
    }
    setSuccess(done.join(' '));
    await reload();
  };
  // AFF-SIGNUP-18: an Owner or Manager checked that a login joined on the
  // phone alone under another name is the customer after all.
  const submitSame = async (note: string): Promise<string | null> => {
    if (!sameFor) return null;
    const m = sameFor;
    setBusy(m.match_id); setErr(null); setSuccess(null);
    const { data, error } = await supabase.rpc('confirm_affiliate_signup_same_person', { p_match_id: m.match_id, p_note: note.trim() });
    setBusy(null);
    if (error) return error.message;
    if (data && typeof data === 'object' && (data as any).ok === false) {
      await reload();
      return (data as any).message ?? 'This sign-up was already checked.';
    }
    setSuccess(`${m.customer_name}: checked as the same person. The login stays on their record.`);
    await reload();
    return null;
  };
  // AFF-SIGNUP-18: the fix when it is someone else, an Owner's Unlink login
  // on the record the login joined (the directory row, when it is loaded).
  const unlinkJoined = (m: SignupMatch) => {
    const row = rows.find(r => r.customer_id === m.customer_id);
    void openUnlink(row ?? ({ customer_id: m.customer_id, name: m.customer_name } as DirRow), m);
  };
  const submitKeep = async (reason: string): Promise<string | null> => {
    if (!keepFor) return null;
    const m = keepFor;
    setBusy(m.match_id); setErr(null); setSuccess(null);
    const { data, error } = await supabase.rpc('keep_affiliate_signup_separate', { p_match_id: m.match_id, p_note: reason.trim() });
    setBusy(null);
    if (error) return error.message;
    if (data && typeof data === 'object' && (data as any).ok === false) {
      await reload();
      return (data as any).message ?? 'This sign-up was already answered.';
    }
    setSuccess(`${m.customer_name} is kept as a separate customer.`);
    await reload();
    return null;
  };

  // 425: an Owner or Manager checks a sign-up that shares a customer's phone.
  const submitDecide = async () => {
    if (!decideFor) return;
    const note = decideNote.trim();
    if (!note) { setDecideErr('Write how you checked this sign-up.'); return; }
    const { check, decision } = decideFor;
    setBusy(check.check_id); setDecideErr(null); setErr(null); setSuccess(null);
    const { data, error } = await supabase.rpc('decide_referral_signup_check',
      { p_check_id: check.check_id, p_decision: decision, p_note: note });
    setBusy(null);
    if (error) { setDecideErr(error.message); return; }
    if (data && typeof data === 'object' && (data as any).ok === false) {
      setDecideErr((data as any).message ?? 'This sign-up was already checked.');
      await reload(); return;
    }
    setDecideFor(null); setDecideNote('');
    setSuccess(decision === 'different_person'
      ? `${check.customer_name} is checked as a different person and now counts for referral promotions.`
      : `${check.customer_name} is checked as the same person and does not count for referral promotions.`);
    await reload();
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

  const openUnlink = async (r: DirRow, from: SignupMatch | null = null) => {
    setUnlinkFor(r); setUnlinkInfo(null); setUnlinkErr(null); setUnlinkReason(''); setUnlinkUnavailable(false);
    setUnlinkFrom(from);
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

      {/* 425: link sign-ups on a customer's phone under another name. They
          count for a referral promotion once checked as a different person. */}
      {canManage && signupChecksErr && <div className="card" data-error="signup-checks" style={{ padding: 12, marginBottom: 12, borderColor: 'var(--danger)', color: 'var(--danger)', fontSize: 13.5 }}>The sign-ups to check could not be loaded: {signupChecksErr}</div>}
      {canManage && signupChecks.length > 0 && (
        <div className="card" data-section="signup-checks" style={{ padding: 16, marginBottom: 16, borderColor: 'var(--warning)' }}>
          <h3 style={{ fontSize: 14, fontWeight: 600, marginBottom: 6, display: 'flex', gap: 8, alignItems: 'center' }}>
            <PhoneCall size={16} /> Check these sign-ups ({signupChecks.length})
          </h3>
          <p style={{ fontSize: 12.5, color: 'var(--text-muted)', marginBottom: 10 }}>
            Each signed up through a referral link with the phone of a customer we already have, under another name.
            It may be a family member, or the same person writing their name another way. They do not count for a
            referral promotion until you check them as a different person.
          </p>
          <div style={{ overflow: 'auto' }}>
            <table className="table" style={{ width: '100%' }}>
              <thead><tr><th>Signed up as</th><th>Phone</th><th>Referred by</th><th>Phone already used by</th><th>When</th><th></th></tr></thead>
              <tbody>
                {signupChecks.map(c => (
                  <tr key={c.check_id} data-check={c.check_id}>
                    <td>{c.customer_name}{c.customer_deleted && <small style={{ color: 'var(--text-muted)' }}> (deleted)</small>}</td>
                    <td>{c.phone ?? '—'}</td>
                    <td>{c.referrer_name ?? '—'}</td>
                    <td>{c.shares_with.length === 0 ? '—' : c.shares_with.map(o => (
                      <div key={o.customer_id}>{o.name}{o.deleted ? ' (deleted)' : ''}
                        <small style={{ color: 'var(--text-muted)' }}> · {o.paid_invoices === 1 ? '1 paid invoice' : `${o.paid_invoices} paid invoices`}</small></div>
                    ))}</td>
                    <td>{d(c.signed_up_at)}</td>
                    <td style={{ textAlign: 'right', whiteSpace: 'nowrap' }}>
                      <button className="btn btn-secondary btn-sm" disabled={busy === c.check_id} style={{ marginRight: 6 }}
                        onClick={() => { setDecideFor({ check: c, decision: 'different_person' }); setDecideNote(''); setDecideErr(null); }}>Different person</button>
                      <button className="btn btn-secondary btn-sm" disabled={busy === c.check_id}
                        onClick={() => { setDecideFor({ check: c, decision: 'same_person' }); setDecideNote(''); setDecideErr(null); }}>Same person</button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}

      {/* 437: new affiliates on a fresh record that may be a customer already
          there. Linking joins the fresh record into that customer. */}
      {canManage && matchesErr && <div className="card" data-error="signup-matches" style={{ padding: 12, marginBottom: 12, borderColor: 'var(--danger)', color: 'var(--danger)', fontSize: 13.5 }}>The new affiliates to check could not be loaded: {matchesErr}</div>}
      {canManage && matches.length > 0 && (
        <div className="card" data-section="signup-matches" style={{ padding: 16, marginBottom: 16, borderColor: 'var(--warning)' }}>
          <h3 style={{ fontSize: 14, fontWeight: 600, marginBottom: 6, display: 'flex', gap: 8, alignItems: 'center' }}>
            <Users size={16} /> New affiliates who may already be customers ({matches.length})
          </h3>
          <p style={{ fontSize: 12.5, color: 'var(--text-muted)', marginBottom: 10 }}>
            Each signed up as an affiliate and was given a new customer record, but their phone, email or name matches a
            customer we already have. They can already use their portal. If it is the same person, link them: the new record
            joins the existing customer, with the affiliate login, referral code and any referrals made since. If it is
            someone else, keep them separate. Those marked "May be someone else" were let into a customer's account on
            the phone alone, under another name: check who they are.
          </p>
          <div style={{ overflow: 'auto' }}>
            <table className="table" style={{ width: '100%' }}>
              <thead><tr><th>Signed up as</th><th>Phone</th><th>Why listed</th><th>May be</th><th></th></tr></thead>
              <tbody>
                {matches.map(m => isSomeoneElse(m) ? (
                  // AFF-SIGNUP-18: joined on the phone alone under another
                  // name. The join stays; staff check who it is. No Link
                  // (there is no new record) and no Keep separate.
                  <tr key={m.match_id} data-match={m.match_id} data-kind="may-be-someone-else">
                    <td>{m.entered_name ?? m.customer_name}
                      <br /><small style={{ color: 'var(--text-muted)' }}>{m.login_email ?? ''}</small>
                      <br /><small style={{ color: 'var(--text-muted)' }}>
                        {`Joined ${d(m.signed_up_at)}`}{m.referral_code ? ` · ${m.referral_code}` : ''}
                      </small>
                    </td>
                    <td>{m.phone ?? m.entered_phone ?? '—'}</td>
                    <td style={{ maxWidth: 220, fontSize: 12.5 }}>{MATCH_REASON.phone_other_name}
                      <div style={{ marginTop: 4 }}>
                        <span className="badge badge-danger" data-flag="someone-else">May be someone else</span>
                      </div>
                    </td>
                    <td>
                      <div data-note="someone-else" role="note" style={{ fontSize: 12.5, maxWidth: 380, lineHeight: 1.5 }}>
                        <div data-detail="typed-name"><b>Name they typed:</b> {m.entered_name ?? '—'}</div>
                        <div data-detail="record-name"><b>The record's name:</b> {m.customer_name}</div>
                        <div style={{ color: 'var(--text-muted)', marginTop: 4 }}>
                          {`${m.entered_name ?? 'They'} signed up on ${m.phone ?? m.entered_phone ?? 'the phone'} and was let into `
                            + `${m.customer_name}'s affiliate account on the phone alone: they see ${m.customer_name}'s portal. `
                            + 'If it is the same person (their name written another way), press Same person. '
                            + `If it is someone else (a family member on the same phone, say), an Owner unlinks the login from ${m.customer_name} `
                            + '(Unlink login); they get a customer record of their own at their next sign-in.'}
                        </div>
                      </div>
                    </td>
                    <td style={{ textAlign: 'right', whiteSpace: 'nowrap' }}>
                      <button type="button" className="btn btn-secondary btn-sm" data-action="same-person" disabled={busy === m.match_id}
                        onClick={() => setSameFor(m)}>Same person</button>
                      {canUnlink && (
                        <button type="button" className="btn btn-secondary btn-sm" data-action="unlink-joined" disabled={busy === m.match_id}
                          onClick={() => unlinkJoined(m)} style={{ marginLeft: 6, gap: 4 }}><Unlink size={13} /> Unlink login</button>
                      )}
                    </td>
                  </tr>
                ) : (
                  <tr key={m.match_id} data-match={m.match_id}>
                    <td>{m.customer_name}
                      <br /><small style={{ color: 'var(--text-muted)' }}>{m.login_email ?? m.email ?? ''}</small>
                      <br /><small style={{ color: 'var(--text-muted)' }}>
                        {`Joined ${d(m.signed_up_at)}`}{m.referral_code ? ` · ${m.referral_code}` : ''}
                        {m.referrals > 0 ? ` · ${m.referrals === 1 ? '1 referral' : `${m.referrals} referrals`}` : ''}
                      </small>
                    </td>
                    <td>{m.phone ?? m.entered_phone ?? '—'}</td>
                    <td style={{ maxWidth: 220, fontSize: 12.5 }}>{MATCH_REASON[m.reason] ?? m.reason}
                      {m.twin && (
                        <div style={{ marginTop: 4 }}>
                          <span className="badge badge-danger" data-flag="twin-entry"
                            title="A customer with the very same name and phone already has an affiliate login.">Twin records</span>
                        </div>
                      )}
                      {/* AFF-SIGNUP-16: what of theirs waits under To match. */}
                      {waitingText(m) && (
                        <div data-note="waiting" style={{ marginTop: 4, color: 'var(--text-muted)' }}>{waitingText(m)}</div>
                      )}
                    </td>
                    <td>{m.candidates.length === 0 ? '—' : m.candidates.map(c => (
                      <div key={c.customer_id} data-candidate={c.customer_id} style={{ marginBottom: 8 }}>
                        <div style={{ fontWeight: 500 }}>{c.name}
                          {c.matched_by.map(k => (
                            <span key={k} className="badge badge-muted" style={{ marginLeft: 6 }}>{MATCHED_BY[k] ?? k}</span>
                          ))}
                          {c.protected && (
                            <span className="badge badge-danger" data-flag="protected" style={{ marginLeft: 6 }}
                              title="An Owner unlinked a login from this customer, or an Owner or Manager rejected a claim for them.">Protected</span>
                          )}
                          {c.twin && (
                            <span className="badge badge-danger" data-flag="twin" style={{ marginLeft: 6 }}
                              title="The very same name and phone as the new record, and an affiliate login of their own.">Same name and phone</span>
                          )}
                        </div>
                        <small style={{ color: 'var(--text-muted)' }}>{[c.phone, c.email].filter(Boolean).join(' · ') || '—'}</small>
                        {c.own_referral_code && !c.problem && (
                          <div data-note="own-code" style={{ fontSize: 12, color: 'var(--text-muted)' }}>
                            {`Has their own affiliate code ${c.own_referral_code}, kept if linked.`}
                          </div>
                        )}
                        <div style={{ marginTop: 4 }}>
                          <button type="button" className="btn btn-secondary btn-sm" data-action="link"
                            disabled={busy === m.match_id || !!c.problem} title={c.problem ?? `Link to ${c.name}`}
                            onClick={() => openLink(m, c)} style={{ gap: 4 }}>
                            <CheckCircle2 size={13} /> Link to this customer
                          </button>
                          {c.problem && <div data-note="cannot-link" style={{ fontSize: 12, color: 'var(--text-muted)', marginTop: 4 }}>{c.problem}</div>}
                        </div>
                        {/* AFF-SIGNUP-13: two records with one name and phone hold
                            this person's website and QR forms until sorted out.
                            The Affiliates list then shows two rows with that name,
                            each with Unlink login: the note names the right one by
                            its referral code, and the new sign-up's. */}
                        {c.twin && (
                          <div data-note="twin" role="note" style={{ fontSize: 12, color: 'var(--danger)', marginTop: 4, maxWidth: 380, lineHeight: 1.5 }}>
                            <b>Twin records.</b> {m.customer_name} has the same name and phone as {c.name}, whose record already
                            has an affiliate login. Until this is sorted out, this person's website registrations, VIP payments and
                            QR health forms will wait under To match. {c.own_referral_code
                              ? `To fix it, an Owner first unlinks the wrong login from ${c.name}: in the Affiliates list below, use Unlink login`
                                + ` on the ${c.name} row with referral code ${c.own_referral_code}`
                                + (m.referral_code && m.referral_code !== c.own_referral_code
                                  ? `, not the one with code ${m.referral_code} (that one is this new sign-up)` : '')
                                + `. Then link this sign-up to ${c.name} here.`
                              : `To fix it, an Owner first unlinks the wrong login from ${c.name} (Unlink login, on ${c.name}'s row in`
                                + ` the Affiliates list below), then links this sign-up to ${c.name} here.`}
                          </div>
                        )}
                      </div>
                    ))}</td>
                    <td style={{ textAlign: 'right', whiteSpace: 'nowrap' }}>
                      <button type="button" className="btn btn-secondary btn-sm" data-action="keep-separate" disabled={busy === m.match_id}
                        onClick={() => setKeepFor(m)}>Keep separate</button>
                    </td>
                  </tr>
                ))}
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
            <thead><tr><th>Affiliate</th><th>Status</th><th>Referral Code</th><th>Referral Link</th>{canDownline && <th></th>}</tr></thead>
            <tbody>
              {loading && <tr><td colSpan={canDownline ? 5 : 4} style={{ textAlign: 'center', padding: 20, color: 'var(--text-muted)' }}>Loading…</td></tr>}
              {!loading && staffRows.length === 0 && <tr><td colSpan={canDownline ? 5 : 4} style={{ textAlign: 'center', padding: 20, color: 'var(--text-muted)' }}>No affiliates found</td></tr>}
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
                  {canDownline && <td>
                    <button type="button" className="btn btn-secondary btn-sm"
                      title="Downline: Tier 1 and Tier 2, with visits" aria-label={`Downline of ${r.full_name}`}
                      onClick={() => setDownlineFor({ customer_id: r.customer_id, name: r.full_name })}><Users size={14} /></button>
                  </td>}
                </tr>
              ))}
            </tbody>
          </table>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', padding: '8px 12px', fontSize: 12.5, color: 'var(--text-muted)', flexWrap: 'wrap', gap: 8 }}>
            <span>{staffTotal === 0 ? 'No affiliates' : `${(staffPage - 1) * STAFF_PAGE + 1}–${Math.min(staffPage * STAFF_PAGE, staffTotal)} of ${staffTotal}`}</span>
            <span style={{ display: 'flex', gap: 6 }}>
              <button type="button" className="btn btn-secondary btn-sm" disabled={staffPage <= 1} onClick={() => void loadStaffPage(staffPage - 1)}>Previous</button>
              <button type="button" className="btn btn-secondary btn-sm" disabled={staffPage * STAFF_PAGE >= staffTotal} onClick={() => void loadStaffPage(staffPage + 1)}>Next</button>
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
                      <button className="btn btn-secondary btn-sm" title="Correct referrer" aria-label={`Correct referrer of ${r.name}`} onClick={() => void openFix(r)} style={{ marginRight: 6 }}><Edit3 size={14} /></button>
                      {suspended
                        ? <button className="btn btn-secondary btn-sm" disabled={busy === r.customer_id} onClick={() => reactivate(r)} style={{ gap: 4 }}><PlayCircle size={14} /> Reactivate</button>
                        : <button className="btn btn-secondary btn-sm" disabled={busy === r.customer_id} onClick={() => setSuspendFor(r)} style={{ gap: 4 }}><Ban size={14} /> Suspend</button>}
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
        <Modal title={`Correct Referrer — ${fixFor.name}`} onClose={closeFix} confirmClose={!!fixRef || !!fixReason.trim()}>
          <p style={{ fontSize: 13, color: 'var(--text-secondary)', marginBottom: 14 }}>
            First valid referral wins, so referrers can only be changed here with a reason (this is audited).
          </p>
          <div data-current-referrer style={{ fontSize: 13, marginBottom: 12, padding: 10, background: 'var(--surface-2)', borderRadius: 'var(--radius-sm)' }}>
            {fixCurrentErr ? <span style={{ color: 'var(--danger)' }}>The current referrer could not be read: {fixCurrentErr}</span>
              : !fixCurrent ? <span style={{ color: 'var(--text-muted)' }}>Reading the current referrer…</span>
              : fixCurrent.id ? <>Current referrer: <strong>{fixCurrent.name ?? 'Name unavailable'}</strong>{fixCurrent.since ? `, since ${d(fixCurrent.since)}` : ''}</>
              : <>Current referrer: <strong>None</strong></>}
          </div>
          <label style={{ display: 'block', fontSize: 13, fontWeight: 600, marginBottom: 6 }}>New Referrer (customer)</label>
          <div style={{ marginBottom: 12 }}><CustomerSearchSelect value={fixRef} onChange={v => { setFixRef(v); setFixRemove(false); }} /></div>
          {fixUnchanged && fixCurrent?.id && <div data-note="same-referrer" style={{ fontSize: 12.5, color: 'var(--text-muted)', marginBottom: 12 }}>This is already the referrer. Choose another customer, or leave it blank to remove the referrer.</div>}
          {fixRemoving && (
            <label data-remove-referrer style={{ display: 'flex', gap: 8, alignItems: 'flex-start', fontSize: 13, marginBottom: 12, color: 'var(--danger)' }}>
              <input type="checkbox" checked={fixRemove} onChange={e => setFixRemove(e.target.checked)} style={{ marginTop: 3 }} />
              <span>Remove {fixCurrent?.name ?? 'the current referrer'} as the referrer. {fixFor.name} will have no referrer, and no one earns commission on their purchases from now on.</span>
            </label>
          )}
          <label style={{ display: 'block', fontSize: 13, fontWeight: 600, marginBottom: 6 }}>Reason (required)</label>
          <textarea className="input" rows={3} value={fixReason} onChange={e => setFixReason(e.target.value)} style={{ marginBottom: 14 }} />
          <div style={{ display: 'flex', gap: 8, justifyContent: 'flex-end' }}>
            <button className="btn btn-secondary" onClick={closeFix}>Cancel</button>
            <button className="btn btn-primary" disabled={busy === fixFor.customer_id || fixBlocked} onClick={submitFix}>{fixRemoving ? 'Remove Referrer' : 'Save Correction'}</button>
          </div>
        </Modal>
      )}

      {/* Suspend: the reason is required (AFFILIATES-8). */}
      {suspendFor && (
        <ReasonModal title={`Suspend ${suspendFor.name}?`} label="Reason" placeholder="Why is this affiliate suspended?"
          confirmLabel="Suspend" onSubmitAsync={submitSuspend} onClose={() => setSuspendFor(null)} />
      )}

      {/* 425: check a sign-up that shares a customer's phone. */}
      {decideFor && (
        <Modal title={decideFor.decision === 'different_person' ? `${decideFor.check.customer_name} is a different person` : `${decideFor.check.customer_name} is the same person`}
          onClose={() => setDecideFor(null)} confirmClose={!!decideNote.trim()}
          footer={<><button className="btn btn-secondary" onClick={() => setDecideFor(null)}>Cancel</button>
            <button className="btn btn-primary" disabled={busy === decideFor.check.check_id || !decideNote.trim()} onClick={() => void submitDecide()}>
              {decideFor.decision === 'different_person' ? 'Count them' : 'Do not count them'}</button></>}>
          <p style={{ fontSize: 13, color: 'var(--text-secondary)', marginBottom: 12 }}>
            {decideFor.decision === 'different_person'
              ? `${decideFor.check.customer_name} shares a phone with ${decideFor.check.shares_with.map(o => o.name).join(', ') || 'another customer'} but is someone else. They count for referral promotions from now on.`
              : `${decideFor.check.customer_name} is ${decideFor.check.shares_with.map(o => o.name).join(' or ') || 'a customer we already have'}, written another way. They never count for a referral promotion. The two records stay as they are; ask the Owner to merge them.`}
          </p>
          <label style={{ display: 'block', fontSize: 13, fontWeight: 600, marginBottom: 6 }}>How did you check? (required)</label>
          <textarea className="input" rows={3} value={decideNote} onChange={e => { setDecideNote(e.target.value); setDecideErr(null); }} />
          {decideErr && <div role="alert" style={{ fontSize: 12.5, color: 'var(--danger)', marginTop: 6 }}>{decideErr}</div>}
        </Modal>
      )}

      {/* 437: link a new affiliate to the customer already there */}
      {linkMatch && (() => {
        const { match, cand } = linkMatch;
        const linking = busy === match.match_id;
        // AFF-SIGNUP-12: the phone and email they signed up with.
        const signupPhone = match.entered_phone;
        const signupEmail = match.login_email ?? match.email;
        const offerPhone = phoneBoxOffered(match, cand);
        // AFF-SIGNUP-16: how the box started, and why, as the server says.
        const startTicked = offerPhone && !!cand.use_signup_phone_default;
        const why = cand.use_signup_phone_why ?? [];
        const seminar = match.waiting?.seminar ?? 0;
        const qr = match.waiting?.qr ?? 0;
        const waitingParts = [
          why.includes('waiting_seminar') && seminar > 0 ? `${seminar} seminar ${seminar === 1 ? 'registration' : 'registrations'}` : null,
          why.includes('waiting_qr') && qr > 0 ? `${qr} QR health ${qr === 1 ? 'form' : 'forms'}` : null,
        ].filter(Boolean) as string[];
        const startReasons = [
          ...why.filter(w => PHONE_WHY[w]).map(w => PHONE_WHY[w](cand.name)),
          ...(waitingParts.length > 0
            ? [`${waitingParts.join(' and ')} for this sign-up ${seminar + qr === 1 ? 'is' : 'are'} waiting under To match`] : []),
        ];
        const emailOnLink = cand.email_on_link ?? (cand.email ? 'keep_own' : signupEmail ? 'copy' : 'none');
        // AFF-SIGNUP-9 and -14: linked to a customer with an affiliate record
        // of their own, the new record's code is retired.
        const retires = cand.retires_new_code ?? !!cand.own_referral_code;
        return (
        <Modal title={`Link the new record to ${cand.name}`}
          onClose={() => { if (!linking) setLinkMatch(null); }} confirmClose={!!linkNote.trim() || linkUsePhone !== startTicked}
          footer={<><button className="btn btn-secondary" disabled={linking} onClick={() => setLinkMatch(null)}>Cancel</button>
            <button className="btn btn-primary" data-action="confirm-link" disabled={linking}
              onClick={() => void submitLink()}>{linking ? 'Linking…' : 'Link to this customer'}</button></>}>
          {/* Who is who: the names alone can be the same. */}
          <div data-detail="link-records" style={{ fontSize: 13, marginBottom: 12, lineHeight: 1.6 }}>
            <div data-detail="new-record"><b>New record:</b> {match.customer_name} · {match.phone ?? match.entered_phone ?? '—'} · {match.login_email ?? match.email ?? '—'}</div>
            <div data-detail="existing-customer"><b>Existing customer:</b> {cand.name} · {cand.phone ?? '—'} · {cand.email ?? '—'}</div>
          </div>
          {/* Both phones; the customer's changes only when ticked (AFF-SIGNUP-12). */}
          <div data-detail="phones" style={{ fontSize: 13, marginBottom: 12, lineHeight: 1.6 }}>
            <div data-detail="customer-phone"><b>{cand.name}'s phone:</b> {cand.phone ?? '—'}</div>
            <div data-detail="signup-phone"><b>The phone they signed up with:</b> {signupPhone ?? '—'}</div>
            {offerPhone ? (
              <>
                <label data-field="use-signup-phone" style={{ display: 'flex', gap: 8, alignItems: 'flex-start', marginTop: 6 }}>
                  <input type="checkbox" checked={linkUsePhone} disabled={linking}
                    onChange={e => { setLinkUsePhone(e.target.checked); setLinkErr(null); }} style={{ marginTop: 3 }} />
                  <span>Use the phone they signed up with</span>
                </label>
                {startTicked && startReasons.length > 0 && (
                  <div data-note="phone-default" style={{ fontSize: 12.5, color: 'var(--text-secondary)', marginTop: 2 }}>
                    {`Ticked to start: ${startReasons.join('; ')}.`}
                  </div>
                )}
                <div data-note="phone-outcome" style={{ fontSize: 12.5, color: linkUsePhone ? 'var(--text-muted)' : 'var(--danger)' }}>
                  {linkUsePhone
                    ? `${cand.name}'s phone becomes ${signupPhone}, as a phone change on the Customers page: the old number goes into the phone history, and at most 3 customers may share a phone.`
                    : `${cand.name} keeps ${cand.phone ?? 'no phone'}. A later website or referral-page registration on ${signupPhone} `
                      + `will not find ${cand.name}: it becomes a new customer and, through another affiliate's link, can earn that `
                      + 'affiliate commission (for a seminar VIP at once).'}
                </div>
              </>
            ) : signupPhone && cand.phone ? (
              <div data-note="phone-outcome" style={{ fontSize: 12.5, color: 'var(--text-muted)' }}>The same phone.</div>
            ) : null}
          </div>
          <p data-detail="email" style={{ fontSize: 13, color: 'var(--text-secondary)', marginBottom: 12 }}>
            {emailOnLink === 'copy'
              ? `${cand.name} has no email: the one they signed up with, ${signupEmail}, will be copied onto them.`
              : emailOnLink === 'in_use'
                ? `${cand.name} has no email, but another customer already has the one they signed up with (${signupEmail}), so it will not be copied.`
                : emailOnLink === 'keep_own'
                  ? `${cand.name} keeps their own email${cand.email ? `, ${cand.email}` : ''}.`
                  : `${cand.name} has no email, and there is none from their sign-up to copy.`}
          </p>
          {retires && match.referral_code && (
            <p role="alert" data-warning="retired-code" style={{ fontSize: 13, color: 'var(--danger)', marginBottom: 12 }}>
              {`Links shared with code ${match.referral_code} will stop crediting anyone. `
                + (cand.own_referral_code
                  ? `Ask them to share code ${cand.own_referral_code} instead.`
                  : `Ask them to share ${cand.name}'s own code instead.`)}
            </p>
          )}
          {cand.protected && (
            <p role="alert" data-flag="protected" style={{ fontSize: 13, color: 'var(--danger)', marginBottom: 12 }}>
              This customer is protected: an Owner unlinked a login from them, or an Owner or Manager rejected a claim for them.
              Link only if you have checked it is the same person.
            </p>
          )}
          <p style={{ fontSize: 13, color: 'var(--text-secondary)', marginBottom: 12 }}>
            {retires
              ? `The new record ${match.customer_name} joins ${cand.name}. ${cand.name} keeps their own affiliate record`
                + (cand.own_referral_code ? ` and referral code ${cand.own_referral_code}` : '') + ', and the affiliate login moves onto it'
                + (match.referral_code ? `; the new record's code ${match.referral_code} is retired. ` : '. ')
              : `The new record ${match.customer_name} joins ${cand.name}. The affiliate login`
                + (match.referral_code ? `, referral code ${match.referral_code}` : '')
                + ` and ${match.referrals === 1 ? '1 referral' : `${match.referrals} referrals`} move to ${cand.name}; the new record is retired. `}
            The affiliate keeps signing in as before. This cannot be undone from the app.
          </p>
          {/* AFF-SIGNUP-17: what Link does with the new record's paid invoices. */}
          <p data-note="commission-on-link" style={{ fontSize: 12.5, color: 'var(--text-muted)', marginBottom: 12 }}>
            {`If ${cand.name} has a referrer, paid invoices on the new record that earned no commission earn it for them now, `
              + 'as at payment, dated today. You will see what was earned once it is linked.'}
          </p>
          <label style={{ display: 'block', fontSize: 13, fontWeight: 600, marginBottom: 6 }}>Note (optional, kept in the Audit Log)</label>
          <textarea className="input" rows={2} value={linkNote} onChange={e => { setLinkNote(e.target.value); setLinkErr(null); }} />
          {linkErr && <div role="alert" data-error="link" style={{ fontSize: 12.5, color: 'var(--danger)', marginTop: 6 }}>{linkErr}</div>}
        </Modal>
        );
      })()}
      {keepFor && (
        <ReasonModal title={`Keep ${keepFor.customer_name} separate`} label="Why are they a different person?"
          placeholder="For example: a family member sharing the phone" confirmLabel="Keep separate"
          onSubmitAsync={submitKeep} onClose={() => setKeepFor(null)} />
      )}
      {sameFor && (
        <ReasonModal title={`${sameFor.entered_name ?? 'This sign-up'} is ${sameFor.customer_name}`}
          label="How did you check it is the same person?" placeholder="For example: called them; their name written another way"
          confirmLabel="Same person" onSubmitAsync={submitSame} onClose={() => setSameFor(null)} />
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
                : unlinkFrom && isSomeoneElse(unlinkFrom) && unlinkFrom.customer_id === unlinkFor.customer_id
                  // AFF-SIGNUP-18: opened from a "May be someone else" row.
                  ? <div data-detail="unlink-how"><b>How:</b> at sign-up, on the phone alone, under the name
                      “{unlinkFrom.entered_name ?? '—'}”, which is not this record's name (listed “May be someone else”).</div>
                  // 437: sign-up joins a login to a customer by the phone they
                  // entered (before 437, only when the verified email, phone
                  // and name all matched); Link on this page moves one too.
                  : <div data-detail="unlink-how"><b>How:</b> without an account claim: at sign-up, by the phone they entered, or by Link to this customer on this page.</div>}
            </div>
          )}
          {unlinkInfo?.linked && (
            <>
              <p data-note="unlink-what" style={{ fontSize: 13, color: 'var(--text-secondary)', marginBottom: 12, lineHeight: 1.6 }}>
                Unlinking removes only the link between this login and {unlinkFor.name}, so the customer can be linked again.
                Their affiliate record, referral code and link, referred customers, commissions and payouts stay as they are,
                with {unlinkFor.name} (referrals made with that code while this login was linked too), and the claim history is kept.
                The person can still sign in, but no longer sees this customer's portal: at their next sign-in they are let in at once
                on a customer record and affiliate account of their own (no account claim is made), and they are never linked back
                to {unlinkFor.name} by themselves, even if their email, phone and name all match this customer's record.
              </p>
              <p data-note="after-unlink" style={{ fontSize: 13, color: 'var(--text-secondary)', marginBottom: 12, lineHeight: 1.6 }}>
                Afterwards staff cannot link any login to {unlinkFor.name}, this one or a new one, and sign-up no longer links
                one to them automatically; only an Owner or Manager can link a login to them.
                When the person's new record may be {unlinkFor.name} (the same phone, email or name), it is listed under
                “New affiliates who may already be customers”, with {unlinkFor.name} marked Protected: answer it with Keep separate,
                or Link once you have checked it is {unlinkFor.name} after all.
                There is no claim to reject. To stop the new record's referral link registering referrals, Suspend that affiliate.
                An account claim still waiting from before (sign-up no longer makes them) that suggests {unlinkFor.name} shows
                “Login unlinked before”.
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
