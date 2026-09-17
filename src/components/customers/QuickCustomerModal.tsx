import React, { useCallback, useEffect, useRef, useState } from 'react';
import { AlertTriangle, UserPlus } from 'lucide-react';
import { supabase } from '../../lib/supabase';
import PhoneInput, { isPhoneValid } from '../PhoneInput';
import { phoneErrorMessage } from '../../lib/customer-phones/normalize.mjs';
import './quick-customer.css';

type Candidate = {
  id: string; full_name: string; phone_tail: string;
  created_at: string; name_matches: boolean;
};

const empty = {
  first_name: '', last_name: '', phone: '', email: '',
  date_of_birth: '', gender: '', gender_other: '', occupation: '', notes: '',
};

/**
 * Adding a customer without losing the invoice you were building.
 *
 * The customer is saved on their own the moment they are created, and the
 * invoice around it is untouched either way — so abandoning the invoice
 * afterwards leaves a real customer behind rather than nothing, and closing
 * this without saving leaves the invoice exactly as it was.
 *
 * Before creating, it shows who is already on file under that phone. Three
 * different people may legitimately share a number, so this offers the choice
 * rather than making it: pick the person already there, or say this is somebody
 * new. The candidates carry a name and the last four digits — enough to
 * recognise someone, not enough to learn anything about them.
 */
export const QuickCustomerModal: React.FC<{
  /** Prefills the name when staff typed something into the selector first. */
  initialName?: string;
  onCreated: (customerId: string, fullName: string) => void;
  onPickedExisting: (customerId: string) => void;
  onClose: () => void;
}> = ({ initialName = '', onCreated, onPickedExisting, onClose }) => {
  const [f, setF] = useState({ ...empty, first_name: initialName });
  const [candidates, setCandidates] = useState<Candidate[] | null>(null);
  const [capacity, setCapacity] = useState<{ used: number; remaining: number } | null>(null);
  const [checking, setChecking] = useState(false);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [fieldError, setFieldError] = useState<'first_name' | 'phone' | null>(null);
  const firstRef = useRef<HTMLInputElement | null>(null);
  const phoneRef = useRef<HTMLDivElement | null>(null);
  // One id per attempt: a retry after a lost response returns the customer the
  // first call made instead of creating a second one.
  const requestId = useRef(crypto.randomUUID());

  const on = (k: keyof typeof empty) =>
    (e: React.ChangeEvent<HTMLInputElement | HTMLSelectElement>) =>
      setF(s => ({ ...s, [k]: e.target.value }));

  useEffect(() => { firstRef.current?.focus(); }, []);

  // Escape closes THIS dialog, not the invoice behind it. Captured, so the
  // invoice modal's own handler never sees the key.
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') { e.stopPropagation(); e.preventDefault(); onClose(); }
    };
    document.addEventListener('keydown', onKey, true);
    return () => document.removeEventListener('keydown', onKey, true);
  }, [onClose]);

  const lookFor = useCallback(async (phone: string) => {
    if (!isPhoneValid(phone)) { setCandidates(null); setCapacity(null); return; }
    setChecking(true);
    const { data, error: err } = await supabase.rpc('customer_match_candidates',
      { p_phone: phone, p_name: `${f.first_name} ${f.last_name}`.trim() || null });
    setChecking(false);
    if (err) return;              // the create call reports anything that matters
    const d = data as any;
    setCandidates((d?.candidates ?? []) as Candidate[]);
    setCapacity({ used: Number(d?.used ?? 0), remaining: Number(d?.remaining ?? 3) });
  }, [f.first_name, f.last_name]);

  useEffect(() => {
    const t = setTimeout(() => void lookFor(f.phone), 400);
    return () => clearTimeout(t);
  }, [f.phone, lookFor]);

  const save = async () => {
    if (!f.first_name.trim()) {
      setFieldError('first_name'); setError('Enter a first name.'); firstRef.current?.focus(); return;
    }
    if (!isPhoneValid(f.phone)) {
      setFieldError('phone');
      setError('Enter a valid mobile or phone number, including the country code.');
      phoneRef.current?.querySelector('input')?.focus();
      return;
    }
    setSaving(true); setError(null); setFieldError(null);
    const { data, error: err } = await supabase.rpc('create_customer_quick', {
      p_first_name: f.first_name, p_last_name: f.last_name || null, p_phone: f.phone,
      p_email: f.email || null, p_date_of_birth: f.date_of_birth || null,
      p_gender: f.gender || null, p_gender_other: f.gender_other || null,
      p_occupation: f.occupation || null, p_notes: f.notes || null,
      // Left null on purpose: who referred a customer is their own profile
      // detail, and it is not the invoice's affiliate selection.
      p_referred_by: null,
      p_request_id: requestId.current,
    });
    setSaving(false);
    if (err) {
      // Everything entered stays on screen; nothing is cleared on a failure.
      setError(phoneErrorMessage(err.message));
      if (/phone/i.test(err.message)) setFieldError('phone');
      return;
    }
    const d = data as any;
    onCreated(d.customer_id, d.full_name ?? `${f.first_name} ${f.last_name}`.trim());
  };

  return (
    <div className="quick-customer-backdrop"
         onClick={e => { if (e.target === e.currentTarget) onClose(); }}>
      <div className="quick-customer" role="dialog" aria-modal="true" aria-labelledby="qc-title">
        <div className="quick-customer-head">
          <h3 id="qc-title"><UserPlus size={16} aria-hidden="true" /> Add a customer</h3>
          <button type="button" className="quick-customer-close" aria-label="Close without saving"
            onClick={onClose}>&times;</button>
        </div>

        <div className="quick-customer-body">
          <p className="qc-note">
            The customer is saved on their own as soon as you add them, so they stay on file even
            if you do not finish this invoice.
          </p>

          <div className="qc-grid">
            <label className="qc-field">First name <span aria-hidden="true">*</span>
              <input ref={firstRef} value={f.first_name} onChange={on('first_name')}
                aria-invalid={fieldError === 'first_name' || undefined} />
            </label>
            <label className="qc-field">Last name
              <input value={f.last_name} onChange={on('last_name')} />
            </label>
          </div>

          <div className="qc-field" ref={phoneRef}>
            <label htmlFor="qc-phone">Phone <span aria-hidden="true">*</span></label>
            <PhoneInput value={f.phone} onChange={v => setF(s => ({ ...s, phone: v }))} />
            {checking && <span className="qc-hint">Checking who is already on this number…</span>}
            {!checking && capacity && (
              <span className="qc-hint">
                {capacity.used === 0
                  ? 'Nobody is on file with this number.'
                  : `${capacity.used} of 3 customers already use this number — ${capacity.remaining} left.`}
              </span>
            )}
          </div>

          {candidates && candidates.length > 0 && (
            <div className="qc-candidates">
              <strong>Already on this number</strong>
              <p className="qc-hint">
                Different people can share a phone, so pick the right person or carry on adding
                somebody new.
              </p>
              <ul>
                {candidates.map(c => (
                  <li key={c.id}>
                    <span className="qc-cand-name">
                      {c.full_name}
                      {c.name_matches && <em className="qc-same"> — same name</em>}
                      <span className="qc-hint"> ·····{c.phone_tail}</span>
                    </span>
                    <button type="button" className="btn btn-secondary btn-sm"
                      onClick={() => onPickedExisting(c.id)}>Use this customer</button>
                  </li>
                ))}
              </ul>
            </div>
          )}

          <div className="qc-grid">
            <label className="qc-field">Email
              <input type="email" value={f.email} onChange={on('email')} />
            </label>
            <label className="qc-field">Date of birth
              <input type="date" value={f.date_of_birth} onChange={on('date_of_birth')} />
            </label>
            <label className="qc-field">Gender
              <select value={f.gender} onChange={on('gender')}>
                <option value="">—</option>
                <option value="male">Male</option>
                <option value="female">Female</option>
                <option value="other">Other</option>
              </select>
            </label>
            {f.gender === 'other' && (
              <label className="qc-field">Please describe
                <input value={f.gender_other} onChange={on('gender_other')} />
              </label>
            )}
            <label className="qc-field">Occupation
              <input value={f.occupation} onChange={on('occupation')} />
            </label>
          </div>

          <label className="qc-field">Notes
            <input value={f.notes} onChange={on('notes')} />
          </label>

          {error && (
            <p className="qc-error" role="alert">
              <AlertTriangle size={14} aria-hidden="true" /> {error}
            </p>
          )}
        </div>

        <div className="quick-customer-foot">
          <button type="button" className="btn" onClick={onClose}>Cancel</button>
          <button type="button" className="btn btn-primary" disabled={saving} onClick={save}>
            {saving ? 'Adding…' : 'Add customer'}
          </button>
        </div>
      </div>
    </div>
  );
};

export default QuickCustomerModal;
