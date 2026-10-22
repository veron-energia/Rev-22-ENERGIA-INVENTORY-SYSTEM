import React, { useEffect, useState, useCallback, useMemo, useRef } from 'react';
import { ExcelExportButton } from '../components/ExcelExport';
import { supabase } from '../lib/supabase';
import { useAuth } from '../context/AuthContext';
import { Customer, CustomerGender, isOwnerOrManager } from '../types';
import { Modal } from '../components/ui';
import DeletedCustomersModal from '../components/DeletedCustomersModal';
import { phoneErrorMessage } from '../lib/customer-phones/normalize.mjs';
import PhoneInput, { isPhoneValid } from '../components/PhoneInput';
import { Plus, Pencil, Trash2, Search, Users, RefreshCw, Eye, Phone, ChevronDown, ChevronRight } from 'lucide-react';
import { CustomerSearchSelect } from '../components/SearchSelect';
import { CoverageLine } from '../components/therapy/coverage';
import DownlineModal from '../components/referrals/DownlineModal';
import { visitFilterArgs, visitFilterActive, sgDate, sgDayOf } from '../lib/referral/campaign.mjs';
import { fetchAllCustomerRows } from '../lib/customers/exportPaging.mjs';
import { canEditCustomers, canSeeCustomerProfile } from '../lib/customers/customerRoles.mjs';
import CustomerLoans from '../components/stock-loans/CustomerLoans';
import { walletSourceTiles, purchasesBySource } from '../lib/invoices/walletSources.mjs';

// join_person_name() in the database: the two parts, trimmed, single-spaced,
// with either side allowed to be empty. Mirrored here so the name the form
// shows is the name that gets stored.
export const joinPersonName = (first?: string | null, last?: string | null) =>
  [String(first ?? '').trim(), String(last ?? '').trim()].filter(Boolean).join(' ');

/** A date or a moment from the database, as a Singapore day (dd/mm/yyyy). */
const showDate = (v?: string | null) => (v ? sgDayOf(v) : '—');

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
type CustomerForm = ReturnType<typeof blank>;

/** The form as update_customer stores it: trimmed, blanks as null, the
 *  gender description only beside Other. */
const formValues = (f: CustomerForm): Record<string, string | boolean | null> => ({
  first_name: f.first_name.trim() || null,
  last_name: f.last_name.trim() || null,
  phone: f.phone.trim() || null,
  email: f.email.trim() || null,
  date_of_birth: f.date_of_birth || null,
  gender: f.gender || null,
  gender_other: f.gender === 'other' ? (f.gender_other.trim() || null) : null,
  occupation: f.occupation.trim() || null,
  notes: f.notes.trim() || null,
  is_active: f.is_active,
  referred_by: f.referred_by || null,
});

/** 418: only the fields that changed are sent, so an edit never writes back
 *  a value someone else changed meanwhile, and the history shows exactly
 *  what was changed. */
export const changedFields = (before: CustomerForm, after: CustomerForm) => {
  const a = formValues(before), b = formValues(after);
  const out: Record<string, string | boolean | null> = {};
  for (const k of Object.keys(b)) if (a[k] !== b[k]) out[k] = b[k];
  return out;
};

type Candidate = { id: string; full_name: string; phone_tail: string; name_matches: boolean };

/** Why a list or a customer could not be loaded, in plain words. The app's
 *  own functions already raise plain messages (P0001, and 406's staff check);
 *  anything else (a timeout, a lost connection, a database message) is not
 *  shown to staff, only written to the console. */
export const plainLoadError = (e?: { message?: string; code?: string } | null) => {
  const m = String(e?.message ?? '').trim();
  if (m && (e?.code === 'P0001' || (e?.code === '42501' && !/^permission denied/i.test(m)))) return m;
  if (m) console.error(m);
  return 'Please try again. If it keeps failing, tell the Owner.';
};

const CustomersPage: React.FC = () => {
  const { profile } = useAuth();
  // Owner/Manager: Delete, Deleted Customers, Correct Referrer and changing a
  // filled-in date of birth (the credit Opening balance and Adjust ask the same).
  const canComplete = isOwnerOrManager(profile?.role);
  // 453 (the Owner, 22 Oct 2026): the Profile's figures, purchase timeline
  // and phone history, and the Downline, for the roles that add and edit
  // customers (Staff and Admins too); Inventory Managers keep the Limited view.
  const canProfile = canSeeCustomerProfile(profile?.role);
  // 418: Add, Edit, Change phone and Source are for Owners, Managers and
  // Staff (and the old Admin role). Inventory Managers still find and view
  // customers; the database refuses their changes too.
  const canEdit = canEditCustomers(profile?.role);
  const [showDeleted, setShowDeleted] = useState(false);
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
  const [loading, setLoading] = useState(true);
  // CUSTOMERS-14: a failed search says so, with Retry, rather than "No customers yet".
  const [listErr, setListErr] = useState<string | null>(null);
  // CUSTOMERS-13: only the newest list request's answer is shown.
  const loadSeq = useRef(0);
  const [search, setSearch] = useState('');
  // Phase 14 — customer source: filter + staff correction.
  const [sourceFilter, setSourceFilter] = useState('');
  const [sourceOpts, setSourceOpts] = useState<{ id: string; label: string; requires_details: boolean }[]>([]);
  // 398: visited the centre (customer_centre_visits) and the first visit date.
  const [visitedFilter, setVisitedFilter] = useState<'' | 'visited' | 'not_visited'>('');
  const [visitFrom, setVisitFrom] = useState('');
  const [visitTo, setVisitTo] = useState('');
  const visitArgs = useMemo(() => visitFilterArgs(visitedFilter, visitFrom, visitTo), [visitedFilter, visitFrom, visitTo]);
  const visitFiltered = visitFilterActive(visitedFilter, visitFrom, visitTo);
  // 398: the downline with visits (453: Owner, Admin, Manager and Staff).
  const [downlineFor, setDownlineFor] = useState<Customer | null>(null);
  const [srcFor, setSrcFor] = useState<Customer | null>(null);
  const [srcOptId, setSrcOptId] = useState('');
  const [srcDetails, setSrcDetails] = useState('');
  const [srcReason, setSrcReason] = useState('');
  const [srcErr, setSrcErr] = useState<string | null>(null);
  const [srcBusy, setSrcBusy] = useState(false);
  const [modalOpen, setModalOpen] = useState(false);
  const [editId, setEditId] = useState<string | null>(null);
  const [form, setForm] = useState(blank());
  // 418: the customer as read when Edit opened, and when it was last saved,
  // so only changed fields are sent and an older copy is refused.
  const [originalForm, setOriginalForm] = useState(blank());
  const [editAt, setEditAt] = useState<string | null>(null);
  const [editLoading, setEditLoading] = useState(false);
  // The latest details could not be read when Edit opened: nothing can be
  // saved (there is no updated_at to check against) until Retry reads them.
  const [editLoadErr, setEditLoadErr] = useState<string | null>(null);
  const [editReason, setEditReason] = useState('');
  const editIdRef = useRef<string | null>(null);
  const editCustomerRef = useRef<Customer | null>(null);
  // First Name takes the cursor once the latest details are in (the fields
  // are locked until then, so autoFocus alone finds it locked).
  const firstNameRef = useRef<HTMLInputElement>(null);
  const focusAfterLoad = useRef(false);
  // Add: one request id per window, so a retry returns the customer the first
  // try made; and who already uses the phone (customer_match_candidates).
  const addRequestId = useRef<string>('');
  const [candidates, setCandidates] = useState<Candidate[] | null>(null);
  const [capacity, setCapacity] = useState<{ used: number; remaining: number } | null>(null);
  const [checkingPhone, setCheckingPhone] = useState(false);
  const [saving, setSaving] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [profileFor, setProfileFor] = useState<Customer | null>(null);
  const [profileErr, setProfileErr] = useState<string | null>(null);
  // Phone history, read for the customer whose Profile is open (CUSTOMERS-19).
  const [profilePhones, setProfilePhones] = useState<{ phone: string; reason: string | null; created_at: string }[] | null>(null);
  const profileIdRef = useRef<string | null>(null);
  const [overviewFor, setOverviewFor] = useState<Customer | null>(null);
  const [overview, setOverview] = useState<any>(null);
  const [ovErr, setOvErr] = useState<string | null>(null);
  // CUSTOMERS-13: the customer whose View is open. An answer for anyone else
  // (a slow one, for the customer opened before) is dropped.
  const overviewIdRef = useRef<string | null>(null);
  const [credit, setCredit] = useState<any>(null);
  // 443: the wallet by source and each package or bundle bought (null and
  // none from a server before 443: the categories show, as before).
  const creditTiles = useMemo(() => walletSourceTiles(credit), [credit]);
  const creditBought = useMemo(() => purchasesBySource(credit), [credit]);
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
    if (!newPhone.trim() || !isPhoneValid(newPhone)) { setPhoneErr('Please enter a valid mobile/phone number.'); return; }
    if (!phoneReason.trim()) { setPhoneErr('A reason is required.'); return; }
    setPhoneBusy(true); setPhoneErr(null);
    const { error } = await supabase.rpc('change_customer_phone', { p_customer_id: phoneFor.id, p_new_phone: newPhone.trim(), p_reason: phoneReason.trim() });
    setPhoneBusy(false);
    if (error) { setPhoneErr(phoneErrorMessage(error.message)); return; }
    setPhoneFor(null); load();
  };

  const load = useCallback(async () => {
    const seq = ++loadSeq.current;
    setLoading(true); setListErr(null);
    // Searching and paging happen in the database. The customer table is far
    // too large to hold in the browser, so only one page is ever fetched.
    // Phone history is read per customer, when their Profile opens.
    const [cust, srcs] = await Promise.all([
      supabase.rpc('search_customers', {
        p_query: debouncedSearch.trim() || null,
        p_source: sourceFilter || null,
        p_limit: PAGE_SIZE,
        p_offset: page * PAGE_SIZE,
        ...visitArgs,
      }),
      supabase.rpc('active_customer_source_options'),
    ]);
    // A newer search (typing, paging, a filter) has been sent since: its
    // answer is the one to show, whichever arrives last.
    if (seq !== loadSeq.current) return;
    if (cust.error) {
      setRows([]); setTotalCount(0);
      setListErr(plainLoadError(cust.error));
    } else {
      const list = (cust.data as any[]) ?? [];
      setRows(list as Customer[]);
      setTotalCount(list.length > 0 ? Number(list[0].total_count) : 0);
    }
    if (!srcs.error) setSourceOpts((srcs.data as any[]) ?? []);
    setLoading(false);
  }, [debouncedSearch, sourceFilter, page, visitArgs]);

  useEffect(() => { load(); }, [load]);
  useEffect(() => {
    const t = setTimeout(() => { setDebouncedSearch(search); setPage(0); }, 300);
    return () => clearTimeout(t);
  }, [search]);
  useEffect(() => { setPage(0); }, [sourceFilter, visitArgs]);

  const openOverview = async (c: Customer) => {
    overviewIdRef.current = c.id;
    // CUSTOMERS-13: the previous customer's wallet goes at once, not when the
    // new one arrives.
    setOverviewFor(c); setOverview(null); setOvErr(null); setOvLoading(true);
    setCredit(null); setCreditRows([]);
    const { data, error } = await supabase.rpc('customer_overview', { p_customer_id: c.id });
    if (overviewIdRef.current !== c.id) return;
    setOvLoading(false);
    // CUSTOMERS-14: a failed View says so, with Retry, rather than "Loading…".
    if (error) { setOvErr(plainLoadError(error)); return; }
    setOverview(data ?? {});
    void loadCredit(c.id);
  };
  const closeOverview = () => { overviewIdRef.current = null; setOverviewFor(null); };

  const loadCredit = async (customerId: string) => {
    if (creditStores.length === 0) {
      const { data: st } = await supabase.from('stores').select('id,name').is('deleted_at', null).order('name');
      setCreditStores((st as any[]) ?? []);
    }
    const { data: bal, error: balErr } = await supabase.rpc('customer_credit_balances', { p_customer_id: customerId });
    if (overviewIdRef.current !== customerId) return;
    setCredit(balErr ? null : bal ?? null);
    const { data: st } = await supabase.rpc('customer_credit_statement',
      { p_customer_id: customerId, p_from: null, p_to: null });
    if (overviewIdRef.current !== customerId) return;
    setCreditRows((st as any[]) ?? []);
  };

  const submitCredit = async () => {
    if (!creditForm || !overviewFor) return;
    setCreditBusy(true); setCreditErr(null);
    let error: any = null;
    // 418: the window's request id goes with every press of Confirm, so a
    // second press after a lost answer returns the entry the first one made.
    if (creditForm.mode === 'legacy') {
      ({ error } = await supabase.rpc('add_legacy_credit', {
        p_customer_id: overviewFor.id, p_category: creditForm.category,
        p_amount: Number(creditForm.amount), p_original_purchase_date: creditForm.purchase_date || null,
        p_store_id: creditForm.store_id || null, p_reference_no: creditForm.reference_no || null,
        p_note: creditForm.note, p_effective_date: creditForm.effective_date || null,
        p_request_id: creditForm.request_id,
      }));
    } else {
      ({ error } = await supabase.rpc('adjust_customer_credit', {
        p_customer_id: overviewFor.id, p_category: creditForm.category,
        p_direction: creditForm.direction, p_amount: Number(creditForm.amount),
        p_reason: creditForm.reason, p_reference_no: creditForm.reference_no || null,
        p_effective_date: creditForm.effective_date || null, p_note: creditForm.note || null,
        p_store_id: creditForm.store_id || null,
        p_request_id: creditForm.request_id,
      }));
    }
    setCreditBusy(false);
    if (error) { setCreditErr(error.message); return; }
    setCreditForm(null); await loadCredit(overviewFor.id);
  };
  const openProfile = async (c: Customer) => {
    profileIdRef.current = c.id;
    setProfileFor(c); setProfileStats(null); setTimeline(null); setExpandedInv({});
    setProfilePhones(null); setProfileErr(null);
    // The figures are for Owners, Admins, Managers and Staff (453); an
    // Inventory Manager sees the limited view and asks for nothing.
    if (!canProfile) { setProfileStats({}); return; }
    const [stats, tl, ph] = await Promise.all([
      supabase.rpc('customer_profile_stats', { p_customer_id: c.id }),
      supabase.rpc('customer_purchase_timeline', { p_customer_id: c.id }),
      supabase.from('customer_phone_history').select('phone,reason,created_at')
        .eq('customer_id', c.id).order('created_at', { ascending: false }),
    ]);
    if (profileIdRef.current !== c.id) return;
    if (stats.error) setProfileErr('The figures could not be loaded. ' + plainLoadError(stats.error));
    setProfileStats(stats.data ?? {});
    setTimeline((tl.data as any[]) ?? []);
    setProfilePhones((ph.data as any[]) ?? []);
  };
  const closeProfile = () => { profileIdRef.current = null; setProfileFor(null); };

  const resetPhoneCheck = () => { setCandidates(null); setCapacity(null); setCheckingPhone(false); };
  const openAdd = () => {
    editIdRef.current = null;
    addRequestId.current = crypto.randomUUID();
    const f = blank();
    setForm(f); setOriginalForm(f); setEditId(null); setEditAt(null); setEditLoading(false); setEditLoadErr(null); setEditReason('');
    setOrigReferrer(''); setErr(null); resetPhoneCheck(); setModalOpen(true);
  };
  // The row is read again when Edit opens: the list may be minutes old, and
  // its updated_at is what update_customer checks. The fields stay locked
  // until it arrives, so nothing typed meanwhile is replaced.
  const openEdit = async (c: Customer) => {
    editIdRef.current = c.id;
    editCustomerRef.current = c;
    const f = blank(c);
    setForm(f); setOriginalForm(f); setEditId(c.id); setEditAt(null); setEditLoadErr(null); setEditReason('');
    setOrigReferrer(c.referred_by ?? ''); setErr(null); resetPhoneCheck(); setEditLoading(true); setModalOpen(true);
    const { data, error } = await supabase.from('customers').select('*').eq('id', c.id).maybeSingle();
    if (editIdRef.current !== c.id) return;
    setEditLoading(false);
    if (error || !data) {
      setEditLoadErr(error ? plainLoadError(error) : 'This customer is no longer on the list.');
      return;
    }
    const fresh = blank(data as Customer);
    setForm(fresh); setOriginalForm(fresh); setOrigReferrer((data as any).referred_by ?? '');
    setEditAt((data as any).updated_at ?? null);
    focusAfterLoad.current = true;
  };
  useEffect(() => {
    if (focusAfterLoad.current && !editLoading && editAt) { focusAfterLoad.current = false; firstNameRef.current?.focus(); }
  }, [editLoading, editAt]);
  const closeForm = () => { editIdRef.current = null; setModalOpen(false); };

  // Correct-referrer (Owner/Manager, audited) — first valid referral otherwise wins.
  const [origReferrer, setOrigReferrer] = useState('');
  const [fixOpen, setFixOpen] = useState(false);
  const [fixVal, setFixVal] = useState('');
  const [fixReason, setFixReason] = useState('');
  const [fixBusy, setFixBusy] = useState(false);
  const [fixErr, setFixErr] = useState<string | null>(null);
  const submitFixReferrer = async () => {
    if (!editId) return;
    if (!fixReason.trim()) { setFixErr('A reason is required.'); return; }
    setFixBusy(true); setFixErr(null);
    const { error } = await supabase.rpc('reassign_customer_referrer',
      { p_customer_id: editId, p_new_referrer_id: fixVal || null, p_reason: fixReason.trim() });
    setFixBusy(false);
    if (error) { setFixErr(error.message); return; }
    setOrigReferrer(fixVal); setForm(f => ({ ...f, referred_by: fixVal }));
    // The correction changed the row: take its new updated_at and referrer, so
    // the edit still open is not refused as made on an older copy.
    const { data } = await supabase.from('customers').select('updated_at,referred_by').eq('id', editId).maybeSingle();
    if (data) {
      setEditAt((data as any).updated_at ?? null);
      setOriginalForm(f => ({ ...f, referred_by: (data as any).referred_by ?? '' }));
    }
    setFixOpen(false); setFixReason(''); load();
  };

  // 418: the date-of-birth rule (the Owner, 9 Oct 2026). Staff may fill in a
  // missing date; changing or clearing one already filled in is for an Owner
  // or Manager, with a reason. A phone change needs a reason too.
  const phoneChanged = !!editId && form.phone !== originalForm.phone;
  const dobLocked = !!editId && !!originalForm.date_of_birth && !canComplete;
  const dobChanged = !!editId && !!originalForm.date_of_birth && form.date_of_birth !== originalForm.date_of_birth;
  const needsReason = phoneChanged || dobChanged;

  // Add: who already uses this phone (as on the Invoices page's Add a customer).
  useEffect(() => {
    if (!modalOpen || (editId && !phoneChanged) || !isPhoneValid(form.phone)) { resetPhoneCheck(); return; }
    let live = true;
    const t = setTimeout(async () => {
      setCheckingPhone(true);
      const { data, error } = await supabase.rpc('customer_match_candidates',
        { p_phone: form.phone, p_name: joinPersonName(form.first_name, form.last_name) || null });
      if (!live) return;
      setCheckingPhone(false);
      if (error) { setCandidates(null); setCapacity(null); return; }
      const d = data as any;
      setCandidates(((d?.candidates ?? []) as Candidate[]).filter(c => c.id !== editId));
      setCapacity({ used: Number(d?.used ?? 0), remaining: Number(d?.remaining ?? 3) });
    }, 400);
    return () => { live = false; clearTimeout(t); };
  }, [modalOpen, editId, phoneChanged, form.phone, form.first_name, form.last_name]);

  const handleSave = async () => {
    // 418: without the latest details there is no updated_at to send, and the
    // check for an older copy would be skipped. Save waits for Retry.
    if (editId && !editAt) { setErr('This customer could not be loaded. Press Retry, or close the window and try again.'); return; }
    // A first name is required, matching update_survey_particulars(), which
    // raises 'A first name is required'. A last name is optional — plenty of
    // customers give only one name.
    if (!form.first_name.trim()) { setErr('First name is required.'); return; }
    if ((!editId || phoneChanged) && !form.phone.trim()) { setErr('Phone number is required. Up to 3 non-deleted customers may share a number.'); return; }
    if ((!editId || phoneChanged) && !isPhoneValid(form.phone)) { setErr('Please enter a valid mobile/phone number.'); return; }
    if (editId) {
      // 418: Edit goes through update_customer, which records the old and the
      // new value of every field it changes. Staff no longer write the table.
      const changes = changedFields(originalForm, form);
      if (Object.keys(changes).length === 0) { closeForm(); return; }
      if (needsReason && !editReason.trim()) {
        setErr(phoneChanged ? 'Give a reason for the new phone number.' : 'Give a reason for changing the date of birth.');
        return;
      }
      setSaving(true); setErr(null);
      const { error } = await supabase.rpc('update_customer', {
        p_customer_id: editId, p_changes: changes,
        p_reason: editReason.trim() || null, p_expected_updated_at: editAt,
      });
      if (error && /STALE_CUSTOMER/.test(error.message)) {
        // The row changed after it was read. That may be this window's own
        // last Save, whose answer was lost: if the customer already holds
        // every change, it is saved.
        const { data: now } = await supabase.from('customers').select('*').eq('id', editId).maybeSingle();
        setSaving(false);
        if (editIdRef.current !== editId) return;
        const stored = now ? formValues(blank(now as Customer)) : null;
        if (stored && Object.entries(changes).every(([k, v]) => stored[k] === v)) { closeForm(); load(); return; }
        setErr('This customer was changed after you opened it. Close this window and open it again.');
        return;
      }
      setSaving(false);
      if (error) { setErr(phoneErrorMessage(error.message)); return; }
    } else {
      // Add: create_customer_quick, as on the Invoices page. Its request id
      // makes a second press after a lost answer return the same customer.
      setSaving(true); setErr(null);
      const { error } = await supabase.rpc('create_customer_quick', {
        p_first_name: form.first_name, p_last_name: form.last_name || null, p_phone: form.phone,
        p_email: form.email || null, p_date_of_birth: form.date_of_birth || null,
        p_gender: form.gender || null, p_gender_other: form.gender === 'other' ? (form.gender_other || null) : null,
        p_occupation: form.occupation || null, p_notes: form.notes || null,
        p_referred_by: form.referred_by || null, p_request_id: addRequestId.current,
      });
      setSaving(false);
      if (error) { setErr(phoneErrorMessage(error.message)); return; }
    }
    closeForm(); load();
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

  // The database has already applied the search and the source filter.
  const filtered = rows;

  // The list is server-paginated, so the on-screen rows are only one page.
  // Export re-runs the same search, page by page, in the list's one fixed
  // order (409), and fails out loud rather than give a short or doubled file.
  const fetchAllForExport = () => fetchAllCustomerRows<any>(async (limit, offset) => {
    const { data, error } = await supabase.rpc('search_customers', {
      p_query: debouncedSearch.trim() || null,
      p_source: sourceFilter || null,
      p_limit: limit, p_offset: offset,
      ...visitArgs,
    });
    return { data: (data as any[]) ?? null, error };
  });


  return (
    <div>
      {showDeleted && <DeletedCustomersModal onClose={() => setShowDeleted(false)} onRestored={() => void load()} />}
      <div className="page-header">
        <div><h2>Customers</h2><p>Customer database. Up to 3 non-deleted customers may share a phone number across all stores, including inactive customers.</p></div>
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
              { header: 'Created', value: (c: any) => c.created_at ? sgDayOf(c.created_at) : '' },
              { header: 'First Visit', value: (c: any) => c.first_visit_on ? sgDate(c.first_visit_on) : '' },
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
              { header: 'Date of Birth', value: (c: any) => c.date_of_birth ? sgDate(c.date_of_birth) : '' },
              { header: 'Gender', value: (c: any) => c.gender ?? '' },
              { header: 'Occupation', value: (c: any) => c.occupation ?? '' },
              { header: 'Address', value: (c: any) => c.address ?? '' },
              // The loaded page does not hold every customer, so a name lookup
              // would print blanks for referrers who are not on screen. The id
              // is exported instead: always correct, and joinable in the sheet.
              { header: 'Referred By (ID)', value: (c: any) => c.referred_by ?? '' },
              // 418 (the Owner, 9 Oct 2026): has referred a customer who is not
              // deleted, or has an affiliate record that is not deleted.
              // search_customers works it out; the stored flag was set on
              // every save.
              { header: 'Is Referrer', value: (c: any) => c.is_referrer ? 'Yes' : 'No' },
              { header: 'Notes', value: (c: any) => c.notes ?? '' },
              { header: 'Created', value: (c: any) => c.created_at ? sgDayOf(c.created_at) : '' },
              { header: 'First Visit', value: (c: any) => c.first_visit_on ? sgDate(c.first_visit_on) : '' },
              { header: 'Status', value: (c: any) => c.is_active ? 'Active' : 'Inactive' },
            ]} />
          <button className="btn btn-secondary" onClick={load}><RefreshCw size={15} className={loading ? 'spin' : ''} /> Refresh</button>
          {canComplete && <button className="btn btn-secondary" onClick={() => setShowDeleted(true)}>Deleted Customers</button>}
          {canEdit && <button className="btn btn-primary" onClick={openAdd}><Plus size={16} /> Add Customer</button>}
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
        {/* 398: a health survey through the centre's own QR link, or a
            consultant's survey with answers, a note or a file; an event's
            survey from a later day's note or file (customer_centre_visits). */}
        <select value={visitedFilter} onChange={e => setVisitedFilter(e.target.value as '' | 'visited' | 'not_visited')}
          style={{ maxWidth: 150 }} title="Visited the centre: a health survey through the centre's own QR link, or a consultant's survey with answers, a note or a file. An event's survey counts only from a later day's note or file." aria-label="Visited">
          <option value="">All customers</option>
          <option value="visited">Visited</option>
          <option value="not_visited">Not visited</option>
        </select>
        <label style={{ display: 'flex', alignItems: 'center', gap: 6, fontSize: 12.5, color: 'var(--text-secondary)' }}>
          First visit
          <input type="date" value={visitFrom} aria-label="First visit from" disabled={visitedFilter === 'not_visited'}
            onChange={e => setVisitFrom(e.target.value)} style={{ width: 145 }} />
          –
          <input type="date" value={visitTo} aria-label="First visit to" disabled={visitedFilter === 'not_visited'}
            onChange={e => setVisitTo(e.target.value)} style={{ width: 145 }} />
        </label>
        {visitFiltered && <button type="button" className="btn btn-secondary btn-sm"
          onClick={() => { setVisitedFilter(''); setVisitFrom(''); setVisitTo(''); }}>Clear visit filters</button>}
      </div>

      <div className="card">
        <div className="table-wrap">
          {loading ? <div className="empty-state"><RefreshCw size={24} className="spin" style={{ opacity: 0.4 }} /></div>
          : listErr ? (
            <div className="empty-state" role="alert">
              <p style={{ fontWeight: 600, marginTop: 8 }}>The customer list could not be loaded.</p>
              <p style={{ fontSize: 12.5, color: 'var(--text-muted)' }}>{listErr}</p>
              <button className="btn btn-secondary btn-sm" style={{ marginTop: 8 }} onClick={() => void load()}><RefreshCw size={13} /> Retry</button>
            </div>
          )
          : filtered.length === 0 ? <div className="empty-state"><Users size={32} style={{ opacity: 0.3 }} /><p style={{ fontWeight: 600, marginTop: 8 }}>{debouncedSearch || sourceFilter || visitFiltered ? 'No customers match this search' : 'No customers yet'}</p></div>
          : (
            <table>
              <thead><tr><th>Name</th><th>Phone</th><th>Email</th><th>Source</th><th title="The first visit to the centre: a health survey through the centre's own QR link, or a consultant's survey with answers, a note or a file">First visit</th><th>Status</th><th></th></tr></thead>
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
                    <td style={{ fontSize: 12.5 }}>{c.first_visit_on ? sgDate(c.first_visit_on) : <span style={{ color: 'var(--text-muted)' }}>—</span>}</td>
                    <td>{c.is_active ? <span className="badge badge-success">Active</span> : <span className="badge badge-muted">Inactive</span>}</td>
                    <td><div style={{ display: 'flex', gap: 4 }}>
                      <button className="btn btn-secondary btn-sm" onClick={() => openOverview(c)}><Eye size={13} /> View</button>
                      <button className="btn btn-secondary btn-sm" onClick={() => openProfile(c)}>Profile</button>
                      {/* 453: Owner, Admin, Manager and Staff, as customer_downline_visits checks. */}
                      {canProfile && <button className="btn btn-secondary btn-sm btn-icon" title="Downline: Tier 1 and Tier 2, with visits"
                        aria-label={`Downline of ${c.full_name}`} onClick={() => setDownlineFor(c)}><Users size={13} /></button>}
                      {canEdit && <>
                        <button className="btn btn-secondary btn-sm btn-icon" title="Change phone" aria-label="Change phone" onClick={() => { setPhoneFor(c); setNewPhone(''); setPhoneReason(''); setPhoneErr(null); }}><Phone size={13} /></button>
                        <button className="btn btn-secondary btn-sm" title="Change customer source (old surveys keep their snapshot)"
                          onClick={() => { setSrcFor(c); setSrcOptId((c as any).source_option_id ?? ''); setSrcDetails((c as any).source_details ?? ''); setSrcReason(''); setSrcErr(null); }}>Source</button>
                        <button className="btn btn-secondary btn-sm btn-icon" title="Edit customer" aria-label="Edit customer" onClick={() => void openEdit(c)}><Pencil size={13} /></button>
                      </>}
                      {/* canComplete is Owner/Manager, matching delete_customer's
                          own check — staff should not be offered a button that
                          the database will refuse. */}
                      {canComplete && <button className="btn btn-danger btn-sm btn-icon"
                        title="Delete customer" aria-label="Delete customer" onClick={() => handleDelete(c)}><Trash2 size={13} /></button>}
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
        <Modal title={editId ? 'Edit Customer' : 'Add Customer'} maxWidth={460} confirmClose onClose={closeForm}
          footer={<><button className="btn btn-secondary" onClick={closeForm}>Cancel</button><button className="btn btn-primary" onClick={handleSave} disabled={saving || editLoading || (!!editId && !editAt)}>{saving ? 'Saving…' : 'Save'}</button></>}>
          <div className="form-grid">
            {err && <div className="alert alert-danger" style={{ marginBottom: 0 }}><span>⚠</span><div>{err}</div></div>}
            {editLoading && <div style={{ fontSize: 12.5, color: 'var(--text-muted)' }}>Loading the latest details…</div>}
            {editLoadErr && (
              <div className="alert alert-danger" role="alert" style={{ marginBottom: 0 }}><span>⚠</span>
                <div>This customer could not be loaded. {editLoadErr}
                  <div><button type="button" className="btn btn-secondary btn-sm" style={{ marginTop: 6 }}
                    onClick={() => { if (editCustomerRef.current) void openEdit(editCustomerRef.current); }}><RefreshCw size={13} /> Retry</button></div>
                </div>
              </div>
            )}
            {/* The fields are locked until the latest details are in. */}
            <fieldset className="form-grid" disabled={editLoading || (!!editId && !editAt)}
              style={{ border: 0, padding: 0, margin: 0, minWidth: 0 }}>
            <div className="form-grid-2">
              {/* Two fields, matching the health survey exactly, so a name
                  entered here needs no splitting to sync across. */}
              <div className="form-grid-2">
                <div className="form-group" style={{ marginBottom: 0 }}>
                  <label>First Name *</label>
                  <input value={form.first_name} autoFocus ref={firstNameRef}
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
              <div className="form-group"><label>Phone * (up to 3 customers)</label><PhoneInput value={form.phone} onChange={(e164) => setForm(f => ({ ...f, phone: e164 }))} />
                {/* Who already uses this number, as on the Invoices page's Add a customer. */}
                {checkingPhone && <span style={{ fontSize: 11.5, color: 'var(--text-muted)', display: 'block', marginTop: 4 }}>Checking who is already on this number…</span>}
                {!checkingPhone && capacity && (
                  <span style={{ fontSize: 11.5, color: 'var(--text-muted)', display: 'block', marginTop: 4 }}>
                    {capacity.used === 0 ? 'Nobody is on file with this number.'
                      : `${capacity.used} of 3 customers already use this number. ${capacity.remaining} left.`}
                  </span>
                )}
                {!checkingPhone && candidates && candidates.length > 0 && (
                  <div style={{ fontSize: 12, marginTop: 4 }} aria-label="Already on this number">
                    <div style={{ fontWeight: 600 }}>Already on this number</div>
                    {candidates.map(c => (
                      <div key={c.id} style={{ color: 'var(--text-secondary)' }}>
                        {c.full_name}{c.name_matches ? ' (same name)' : ''} · ending {c.phone_tail}
                      </div>
                    ))}
                    {!editId && <div style={{ color: 'var(--text-muted)' }}>If this is one of them, close this and search the list instead of adding them again.</div>}
                  </div>
                )}
              </div>
            </div>
            <div className="form-grid-2">
              <div className="form-group"><label>Email</label><input type="email" value={form.email} onChange={e => setForm(f => ({ ...f, email: e.target.value }))} placeholder="Optional" /></div>
              <div className="form-group"><label>Date of Birth</label><input type="date" value={form.date_of_birth} disabled={dobLocked}
                aria-describedby={dobLocked ? 'dob-locked' : undefined}
                onChange={e => setForm(f => ({ ...f, date_of_birth: e.target.value }))} />
                {/* 418: the Owner's rule. The Birthday discount reads this date. */}
                {dobLocked && <span id="dob-locked" style={{ fontSize: 11.5, color: 'var(--text-muted)', display: 'block', marginTop: 4 }}>Only an Owner or Manager can change a date of birth that is already filled in.</span>}
              </div>
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
              {editId && origReferrer ? (
                <>
                  <div className="input" style={{ background: 'var(--surface-2, #f6f6f6)', color: 'var(--text-secondary)', display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
                    <span>Referrer assigned — locked (first valid referral wins)</span>
                    {canComplete && <button type="button" className="btn btn-secondary btn-sm" onClick={() => { setFixVal(origReferrer); setFixReason(''); setFixErr(null); setFixOpen(true); }}>Correct Referrer</button>}
                  </div>
                  <span style={{ fontSize: 11.5, color: 'var(--text-muted)', marginTop: 4, display: 'block' }}>Referrer ownership is locked. Owner/Manager can correct it with a reason (audited).</span>
                </>
              ) : (
                <>
                  <CustomerSearchSelect
                    value={form.referred_by}
                    onChange={v => setForm(f => ({ ...f, referred_by: v }))}
                    placeholder="Search name, phone or email…"
                    excludeId={editId ?? undefined} />
                  <span style={{ fontSize: 11.5, color: 'var(--text-muted)', marginTop: 4, display: 'block' }}>The customer who introduced this customer. Drives Tier 1 / Tier 2 commission.</span>
                </>
              )}
            </div>
            {/* The Owner, 9 Oct 2026: Add has no Active box. A new customer
                starts active; Active is changed by Edit. */}
            {editId && (
              <label style={{ display: 'flex', alignItems: 'center', gap: 8, cursor: 'pointer' }}>
                <input type="checkbox" checked={form.is_active} onChange={e => setForm(f => ({ ...f, is_active: e.target.checked }))} style={{ width: 'auto' }} /><span style={{ fontSize: 13 }}>Active</span>
              </label>
            )}
            {needsReason && (
              <div className="form-group" style={{ marginBottom: 0 }}>
                <label htmlFor="edit-reason">Reason for this change *</label>
                <input id="edit-reason" value={editReason} onChange={e => setEditReason(e.target.value)}
                  placeholder={phoneChanged ? 'Why is the number changing?' : 'Why is the date of birth changing?'} />
                <span style={{ fontSize: 11.5, color: 'var(--text-muted)', marginTop: 4, display: 'block' }}>
                  Kept in the history with the old and the new value.
                </span>
              </div>
            )}
            </fieldset>
          </div>
        </Modal>
      )}

      {fixOpen && (
        <Modal title="Correct Referrer" maxWidth={460} onClose={() => setFixOpen(false)}
          footer={<><button className="btn btn-secondary" onClick={() => setFixOpen(false)}>Cancel</button><button className="btn btn-primary" onClick={submitFixReferrer} disabled={fixBusy}>{fixBusy ? 'Saving…' : 'Save Correction'}</button></>}>
          <div style={{ padding: 4 }}>
            <p style={{ fontSize: 13, color: 'var(--text-secondary)', marginBottom: 14 }}>
              First valid referral normally wins, so this change is audited. Leave the referrer blank to clear it.
            </p>
            <div className="form-group">
              <label>New referrer</label>
              <CustomerSearchSelect value={fixVal} onChange={setFixVal} placeholder="Search name, phone or email…" excludeId={editId ?? undefined} />
            </div>
            <div className="form-group">
              <label>Reason (required)</label>
              <textarea rows={3} value={fixReason} onChange={e => setFixReason(e.target.value)} placeholder="Why is this being changed?" />
            </div>
            {fixErr && <p style={{ color: 'var(--danger)', fontSize: 13 }}>{fixErr}</p>}
          </div>
        </Modal>
      )}

      {overviewFor && (
        <Modal title={`${overviewFor.full_name}`} maxWidth={640} onClose={closeOverview}
          footer={<button className="btn btn-secondary" onClick={closeOverview}>Close</button>}>
          {ovErr ? (
            <div className="alert alert-danger" role="alert" style={{ marginBottom: 0 }}><span>⚠</span>
              <div>This customer could not be loaded. {ovErr}
                <div><button className="btn btn-secondary btn-sm" style={{ marginTop: 6 }} onClick={() => void openOverview(overviewFor)}><RefreshCw size={13} /> Retry</button></div>
              </div>
            </div>
          ) : ovLoading || !overview ? <div style={{ textAlign: 'center', padding: 30, color: 'var(--text-muted)' }}>Loading…</div> : (
            <div style={{ display: 'flex', flexDirection: 'column', gap: 14, fontSize: 13 }}>
              {credit && (
                <section>
                  <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', flexWrap: 'wrap', gap: 6 }}>
                    <div style={{ fontWeight: 700 }}>Credit wallet</div>
                    {isOwnerOrManager(profile?.role) && (
                      <div style={{ display: 'flex', gap: 6 }}>
                        <button className="btn btn-secondary btn-sm" onClick={() => { setCreditErr(null); setCreditForm({ mode: 'legacy', category: 'legacy', amount: '', purchase_date: '', store_id: '', reference_no: '', note: '', effective_date: '', request_id: crypto.randomUUID() }); }}>Opening balance</button>
                        <button className="btn btn-secondary btn-sm" onClick={() => { setCreditErr(null); setCreditForm({ mode: 'adjust', category: 'paid', direction: 'increase', amount: '', reason: '', reference_no: '', note: '', effective_date: '', store_id: '', request_id: crypto.randomUUID() }); }}>Adjust</button>
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
                    {creditTiles ? (
                      // 443 (the Owner, 21 Oct 2026, CREDIT-SPLIT-3, 4, 12): by
                      // where the credit came from, each with its Paid and Bonus.
                      <div style={{ display: 'flex', gap: 14, flexWrap: 'wrap', fontSize: 12 }} data-testid="credit-by-source">
                        {creditTiles.map(g => (
                          <div key={g.source}>
                            <div style={{ color: 'var(--text-muted)' }}>{g.name}</div>
                            <div style={{ fontWeight: 600 }}>S${g.total.toFixed(2)}</div>
                            {g.parts.length > 0 && (
                              <div style={{ fontSize: 11, color: 'var(--text-muted)' }}>
                                {g.parts.map(([n, v]) => `${n} S$${v.toFixed(2)}`).join(' · ')}
                              </div>
                            )}
                          </div>
                        ))}
                      </div>
                    ) : (
                      <div style={{ display: 'flex', gap: 10, flexWrap: 'wrap', fontSize: 12 }}>
                        {(['paid','bonus','legacy','promotional','exchange'] as const).map(k => (
                          <div key={k}>
                            <div style={{ color: 'var(--text-muted)', textTransform: 'capitalize' }}>{k}</div>
                            <div style={{ fontWeight: 600 }}>S${Number(credit.categories?.[k] ?? 0).toFixed(2)}</div>
                          </div>
                        ))}
                      </div>
                    )}
                  </div>
                  {creditBought.length > 0 && (
                    // Each package and bundle bought, with what is left of it
                    // (one used up too, at S$0.00); credit moved in from
                    // another customer's purchase says so.
                    <div style={{ marginTop: 8, fontSize: 12 }} data-testid="credit-purchases">
                      {creditBought.map(g => (
                        <div key={g.source} style={{ marginBottom: 4 }}>
                          <div style={{ color: 'var(--text-muted)' }}>{g.name} bought</div>
                          {g.items.map((b, i) => (
                            <div key={i} style={{ display: 'flex', justifyContent: 'space-between', gap: 8, flexWrap: 'wrap' }}>
                              <span>{b.name}{b.invoiceNo ? ` · ${b.invoiceNo}` : ''}{b.boughtOn ? ` · ${showDate(b.boughtOn)}` : ''}{b.received ? ' · received from another customer' : ''}</span>
                              <span>
                                <strong>S${b.total.toFixed(2)}</strong> left
                                {b.parts.length > 0 && <span style={{ color: 'var(--text-muted)' }}> ({b.parts.map(([n, v]) => `${n} S$${v.toFixed(2)}`).join(' · ')})</span>}
                              </span>
                            </div>
                          ))}
                        </div>
                      ))}
                    </div>
                  )}
                  {creditRows.length > 0 && (
                    <div style={{ marginTop: 8, maxHeight: 190, overflowY: 'auto', border: '1px solid var(--border)', borderRadius: 'var(--radius-sm)' }}>
                      <table style={{ fontSize: 11.5 }}>
                        <thead><tr><th>Date</th><th>Description</th><th>Category</th><th style={{ textAlign: 'right' }}>Added</th><th style={{ textAlign: 'right' }}>Used</th><th style={{ textAlign: 'right' }}>Reversed</th><th style={{ textAlign: 'right' }}>Balance</th></tr></thead>
                        <tbody>
                          {creditRows.map(r => (
                            <tr key={r.entry_seq}>
                              <td>{showDate(r.entry_date)}</td>
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
                  {overview.purchased_therapy.map((t: any, i: number) => <div key={i} style={{ color: 'var(--text-muted)', fontSize: 12 }}>
                    {/* A closed unit says so first; the benefit wording is for open ones. */}
                    {t.no} · {t.package} · {['cancelled', 'refunded', 'expired'].includes(t.status)
                      ? `${t.status}${t.benefit === 'voucher' ? ' (was taken as vouchers)' : ''}`
                      : t.benefit === 'voucher' ? 'taken as vouchers'
                      : t.offers_choice && !t.benefit ? 'not claimed yet — therapy or vouchers'
                      : String(t.status).replace('_', ' ')}
                    {t.benefit !== 'voucher' && t.expiry && !['cancelled', 'refunded', 'expired'].includes(t.status)
                      ? ` · expires ${showDate(t.expiry)}` : ''}
                    {/* What an open unlimited period covers, and each service's own limit. */}
                    {t.benefit !== 'voucher' && !['cancelled', 'refunded', 'expired'].includes(t.status) && (t.covers ?? []).length > 0 && (
                      <CoverageLine services={t.covers}
                        lead={t.expiry && ['active', 'scheduled'].includes(t.status)
                          ? `Unlimited until ${showDate(t.expiry)}:` : 'Covers'} />)}
                  </div>)}
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
                  {overview.deleted_invoices.map((iv: any, i: number) => <div key={i} style={{ color: 'var(--text-muted)', fontSize: 12 }}>{iv.invoice} · S${Number(iv.total).toFixed(2)} · deleted {showDate(iv.deleted_at)}</div>)}
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
            <div className="form-group"><label>New Phone Number *</label><PhoneInput value={newPhone} onChange={(e164) => setNewPhone(e164)} autoFocus /></div>
            <div className="form-group"><label>Reason *</label><input value={phoneReason} onChange={e => setPhoneReason(e.target.value)} placeholder="Why is the number changing?" /></div>
          </div>
        </Modal>
      )}

      {profileFor && (
        <Modal title={`Profile — ${profileFor.full_name}`} maxWidth={460} onClose={closeProfile}
          footer={<button className="btn btn-secondary" onClick={closeProfile}>Close</button>}>
          {!profileStats ? <div className="empty-state"><RefreshCw size={22} className="spin" style={{ opacity: 0.4 }} /></div> : (
            <div className="form-grid">
              {profileErr && <div className="alert alert-danger" role="alert" style={{ marginBottom: 0 }}><span>⚠</span>
                <div>{profileErr} <button className="btn btn-secondary btn-sm" onClick={() => void openProfile(profileFor)}>Retry</button></div></div>}
              {canProfile ? (
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
                    <button type="button" className="btn btn-secondary btn-sm" style={{ marginTop: 6, gap: 4 }}
                      onClick={() => setDownlineFor(profileFor)}><Users size={13} /> Downline</button>
                  </div>
                  <div style={{ padding: 12, background: 'var(--surface-2)', borderRadius: 'var(--radius-sm)' }}>
                    <div style={{ fontSize: 11, color: 'var(--text-muted)' }}>Referred by</div>
                    <div style={{ fontSize: 14, fontWeight: 600, marginTop: 4 }}>{profileStats.referrer_name ?? '—'}</div>
                  </div>
                </div>
              ) : (
                <div className="alert alert-info" style={{ marginBottom: 0 }}><span>ℹ️</span><div>Limited view — purchases, spend, phone history and the downline are visible to Owners, Admins, Managers and Staff.</div></div>
              )}
              <div style={{ fontSize: 12, color: 'var(--text-secondary)', display: 'flex', flexWrap: 'wrap', gap: '4px 14px' }}>
                <span>Phone: {profileFor.phone}</span>
                {profileFor.email && <span>· {profileFor.email}</span>}
                {profileFor.date_of_birth && <span>· DOB: {sgDate(profileFor.date_of_birth)}</span>}
                {profileFor.gender && <span>· {profileFor.gender === 'other' ? (profileFor.gender_other || 'Other') : (profileFor.gender.charAt(0).toUpperCase() + profileFor.gender.slice(1))}</span>}
                {profileFor.occupation && <span>· {profileFor.occupation}</span>}
                {profileFor.first_visit_on !== undefined && <span>· First visit: {profileFor.first_visit_on ? sgDate(profileFor.first_visit_on) : 'not yet'}</span>}
              </div>
              {/* 401: stock lent to this customer or affiliate (the stores the viewer works in). */}
              <CustomerLoans customerId={profileFor.id} />
              {canProfile && (() => {
                const hist = profilePhones ?? [];
                return hist.length > 0 ? (
                  <div>
                    <label>Phone history</label>
                    <div style={{ display: 'flex', flexDirection: 'column', gap: 4, marginTop: 4 }}>
                      {hist.map((h, i) => (
                        <div key={i} style={{ fontSize: 12, color: 'var(--text-secondary)', display: 'flex', justifyContent: 'space-between', borderBottom: '1px solid var(--border)', paddingBottom: 3 }}>
                          <span style={{ fontFamily: 'var(--font-display)' }}>{h.phone}</span>
                          <span style={{ color: 'var(--text-muted)' }}>{h.reason || '—'} · {showDate(h.created_at)}</span>
                        </div>
                      ))}
                    </div>
                  </div>
                ) : null;
              })()}
              {canProfile && timeline && timeline.length > 0 && (
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
                              <span style={{ fontSize: 11.5, color: 'var(--text-muted)' }}>{showDate(inv.date)}</span>
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
              {canProfile && timeline && timeline.length === 0 && (
                <div style={{ fontSize: 12.5, color: 'var(--text-muted)' }}>No purchases yet.</div>
              )}
            </div>
          )}
        </Modal>
      )}
      {/* Last, so it opens above the Profile window it can be opened from. */}
      {downlineFor && <DownlineModal customerId={downlineFor.id} name={downlineFor.full_name} onClose={() => setDownlineFor(null)} />}
    </div>
  );
};

export default CustomersPage;
