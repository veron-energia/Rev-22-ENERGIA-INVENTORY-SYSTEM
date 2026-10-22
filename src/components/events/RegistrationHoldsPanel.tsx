import React, { useState } from 'react';
import { AlertTriangle, Link2, RotateCcw, UserPlus, Users, XCircle } from 'lucide-react';
import { supabase } from '../../lib/supabase';
import { Modal } from '../ui';
import { CustomerSearchSelect } from '../SearchSelect';
import {
  EventWebExtras, Guest, HOLD_REASON_LABELS, HoldCandidate, PUT_BACK_TELL_THEM, RegistrationHold, SIGNED_UP_AGAIN_CLOSE_TEXT, candidateGuestText,
  candidateMergedText, doubleVipWarning, fmtDateTime, fmtDayList, holdVipBadge, normalizeGuestRestored, pickedCustomerCandidate, putBackText,
  signedUpAgainText, vipCheckoutCloseNote,
} from './model';

/*
 * Guests → To match (436, as 433's QR forms). A person registered on the
 * event's website whose phone or email belongs to a customer under another
 * name (or whose name matches several), or who gave the name of the affiliate
 * whose link they came through on a phone and email not on her record (the
 * owner, 21 Oct 2026), is on the guest list at once, with no customer, and
 * waits here. Any staff of the event attach them to the right
 * customer (with a note on how they confirmed it) or make a new customer (a
 * family member sharing the phone); an Owner or Manager may close one that is
 * not a real registration. A VIP payment of theirs waits until they are
 * matched, then is invoiced by itself (HitPay) or by a Manager (a transfer).
 *
 * R6-4 (the owner, 21 Oct 2026): someone held because they gave the
 * affiliate's own name (affiliate_name) is most likely the affiliate herself.
 * Staff may still make a new customer (no Owner or Manager needed), but the
 * panel and the New customer window warn first: link her own record unless
 * sure it is someone else; a new customer earns her upline nothing.
 *
 * Round 8 (the owner, 21 Oct 2026: P1): a candidate who is already a guest of
 * this event says so (their days, VIP paid with its invoice or VIP payment
 * waiting). When the held person paid (or waits on) a VIP and the candidate
 * already holds one, the Link window warns first that the customer will have
 * two VIP payments (refund one after linking); linking stays allowed. The
 * review of round 8 (21 Oct 2026): a customer picked with "Find another
 * customer…" is read from the guest list the page has (their rows, VIP paid
 * or waiting), so that window says "Already a guest" and warns the same.
 *
 * 439 (the owner, 21 Oct 2026): a customer they were held for whom a merge has since retired is listed as the record
 * that kept it, with "Merged from <name>, who had this phone" (the kept record may not have that phone itself);
 * linking it links the kept record, and a new customer still waits for the check where the retired record's phone
 * or email made them.
 *
 * 444 (the owner, 21 Oct 2026: "Staff can close it"): a HitPay checkout they opened and left without paying says
 * "Online payment started, not paid (until HH:MM)", not "VIP payment waiting", and does not stop an Owner or Manager
 * closing the registration: the checkout closes with it (if HitPay reports a payment for it later, it waits on Website
 * orders for a refund). A payment taken or a transfer sent still waits on Website orders first, and the refusal says
 * what to do there.
 *
 * 449 (the owner, 22 Oct 2026: "Hold for staff to decide"): someone staff took off the guest list who signs up again on
 * the website with their own email waits here too, as "Signed up again after being taken off the list" (who took them
 * off and why, when they signed up again, the days they asked for). Any staff "Put back on the list" (the Guests tab's
 * Restore: their days and the days asked for now; the hold ends; the website sends them nothing, so staff tell them on
 * WhatsApp and send their VIP link); an Owner or Manager may Close it (they stay off, and an unpaid HitPay checkout of
 * theirs closes with it, as above; if they sign up again they show here again). They already have their customer, so
 * there is nothing to link or make.
 * Someone also waiting to be matched shows once, with both.
 */

/** R6-4: the warning for an affiliate_name hold, naming the affiliate (the server's name, else the candidate with her name). */
export function affiliateHoldWarning(h: RegistrationHold): string | null {
  if (h.reason !== 'affiliate_name') return null;
  const name = h.affiliate_name ?? h.candidates.find(c => c.name_matches)?.full_name ?? h.full_name;
  return `This looks like ${name} herself. Link her own record unless you are sure it is a different person; a new customer earns her upline nothing.`;
}

/** The server's refusal, in words staff can act on here. */
export const explain = (message: string) => {
  if (/CUSTOMER_PHONE_LIMIT/.test(message)) {
    return 'This phone number already belongs to 3 customers, so no new customer can be made with it. '
      + 'Attach the person to one of them, or ask an Owner or Manager to close the registration.';
  }
  // 444: a VIP payment that took money, or a transfer sent, still waits on Website orders (an unpaid checkout no longer does).
  const vip = /^A VIP payment for (.+) is waiting: deal with it on Website orders first\.?$/.exec(message);
  if (vip) {
    return `${vip[1]} has a VIP payment on Website orders that was paid, or a transfer they sent, so the registration `
      + 'cannot be closed yet. On Website orders, create its invoices, or close it as refunded once the money is back '
      + '(dismiss a transfer that never arrived); then close the registration.';
  }
  return message;
};
/** Someone else dealt with it meanwhile: the list is out of date. */
const stale = (message: string) => /not waiting to be matched|already closed|not waiting for staff any more/.test(message);

/** 449: taken off the list and signed up again, and nothing else (not waiting to be matched). */
export const onlySignedUpAgain = (h: Pick<RegistrationHold, 'reason'>): boolean => h.reason === 'signed_up_again';

type Action =
  | { kind: 'attach'; hold: RegistrationHold; customer: HoldCandidate | null }
  | { kind: 'create'; hold: RegistrationHold }
  | { kind: 'close'; hold: RegistrationHold }
  | { kind: 'put_back'; hold: RegistrationHold };

export const RegistrationHoldsPanel: React.FC<{
  holds: RegistrationHold[];
  /** Owner or Manager: may close a registration without matching it. */
  canClose: boolean;
  /** After a person was attached, made a customer or closed. */
  onChanged: () => void;
  /** The event's guest list and website extras: a customer picked with "Find another customer…" is read from them. */
  guests?: Guest[];
  extras?: EventWebExtras | null;
}> = ({ holds, canClose, onChanged, guests = [], extras = null }) => {
  const [action, setAction] = useState<Action | null>(null);
  const [note, setNote] = useState('');
  const [otherId, setOtherId] = useState('');
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [done, setDone] = useState<string | null>(null);

  const open = (a: Action) => { setAction(a); setNote(''); setOtherId(''); setErr(null); setDone(null); };
  const close = () => { if (!busy) setAction(null); };

  const confirm = async () => {
    if (!action) return;
    setBusy(true); setErr(null);
    const h = action.hold;
    const res = action.kind === 'attach'
      ? await supabase.rpc('event_registration_attach', {
          p_person_id: h.person_id, p_customer_id: action.customer?.customer_id ?? otherId, p_note: note.trim() })
      : action.kind === 'create'
        ? await supabase.rpc('event_registration_create_customer', { p_person_id: h.person_id, p_note: note.trim() || null })
        // 449: Put back is the Guests tab's Restore of their free guest record (the server adds the days they asked for).
        : action.kind === 'put_back'
          ? await supabase.rpc('event_set_guest_cancelled', { p_guest_id: h.guest_id, p_cancelled: false, p_reason: note.trim() || null })
          : await supabase.rpc('event_registration_close', { p_person_id: h.person_id, p_reason: note.trim() });
    setBusy(false);
    if (res.error) {
      setErr(explain(res.error.message));
      if (stale(res.error.message)) onChanged();
      return;
    }
    // A VIP payment that waited for this person is invoiced now, or still waits (and why).
    const vip = Array.isArray((res.data as any)?.vip_orders) ? (res.data as any).vip_orders as { order_id: string; status: string; review_reason: string | null }[] : [];
    const vipText = vip.map(v => v.status === 'invoiced'
      ? ` Their VIP payment ${v.order_id} is now invoiced.`
      : ` Their VIP payment ${v.order_id} still waits: ${v.review_reason ?? v.status}.`).join('');
    // 444: their unpaid checkouts closed with the registration.
    const closedCheckouts = Array.isArray((res.data as any)?.checkouts_closed)
      ? ((res.data as any).checkouts_closed as { order_id: string; people?: number }[]) : [];
    const checkoutText = closedCheckouts.map(c => ` Their unpaid online checkout ${c.order_id} was closed too`
      + `${(c.people ?? 1) > 1 ? ` (for all ${c.people} people on it)` : ''}.`).join('');
    // 449: put back (the days added, any the event no longer has dropped), or a signed-up-again hold closed.
    const restored = action.kind === 'put_back' ? normalizeGuestRestored(res.data) : null;
    const putBackDone = restored
      ? `${h.full_name} is back on the guest list.${restored.days_added.length ? ` ${fmtDayList(restored.days_added)} added, as they asked.` : ''}`
        + `${restored.days_dropped.length ? ` ${fmtDayList(restored.days_dropped)} taken off (no longer an event day).` : ''}`
        + ` ${PUT_BACK_TELL_THEM}`
      : '';
    setDone(action.kind === 'attach'
      ? `${h.full_name} is now linked to ${action.customer?.full_name ?? 'the customer you chose'}.${vipText}`
      : action.kind === 'create' ? `A new customer was made for ${h.full_name}.${vipText}`
      : action.kind === 'put_back' ? putBackDone
      : (res.data as any)?.signed_up_again === 'closed' ? `${h.full_name} stays off the guest list.${checkoutText}`
      : `${h.full_name}'s registration was closed.${checkoutText}`);
    setAction(null);
    onChanged();
  };

  // The customer the Link window is about: the candidate clicked, or the one picked with "Find another customer…".
  const picked = action?.kind === 'attach' && !action.customer ? pickedCustomerCandidate(otherId, guests, extras) : null;
  const linkTo = action?.kind === 'attach' ? action.customer ?? picked : null;
  const needsNote = action?.kind === 'attach' || action?.kind === 'close';
  const ready = !!action && (!needsNote || note.trim().length >= 3)
    && !(action.kind === 'attach' && !action.customer && !otherId);

  if (holds.length === 0 && !done) return null;
  return (
    <div className="card events-holds" data-holds>
      <div className="events-holds-head">
        <Users size={16} />
        <strong>To match ({holds.length})</strong>
        <span className="events-sub">
          Registered on the website, but staff must confirm who they are (their phone or email is on another customer's
          record, or they gave the affiliate's own name on a new phone and email). They are on the guest list already; link
          each to the right customer, or make a new one. A VIP payment of theirs waits until then.
          {holds.some(h => h.signed_up_again) && (
            <> Someone taken off the list who signed up again waits here too: put them back on the list, or close it to leave
            them off. The website told them their place will be confirmed.</>
          )}
        </span>
      </div>
      {done && <div className="alert alert-info" role="status"><span>✓</span><div>{done}</div></div>}
      {holds.map(h => (
        <div key={h.person_id} className="events-hold" data-hold={h.person_id}>
          <div className="events-hold-top">
            <div>
              <strong>{h.full_name}</strong>
              {holdVipBadge(h) && (
                <> <span className={holdVipBadge(h)!.kind === 'payment' ? 'badge badge-accent' : 'badge badge-muted'}
                  data-hold-vip={holdVipBadge(h)!.kind}
                  title={holdVipBadge(h)!.kind === 'checkout'
                    ? 'They opened the online payment (HitPay) and did not pay. It does not stop closing the registration.'
                    : 'A VIP payment of theirs waits on Website orders until they are matched'}>
                  {holdVipBadge(h)!.text}
                </span></>
              )}
              <div className="events-sub">
                {[h.phone, h.email].filter(Boolean).join(' · ')}{h.days.length ? ` · ${fmtDayList(h.days)}` : ''}
                {' · '}{h.registration_id} · {h.position} of {h.group_size}{h.held_at ? ` · ${fmtDateTime(h.held_at)}` : ''}
              </div>
              {h.referral_note && <div className="events-sub" data-referral-note>{h.referral_note}</div>}
              {h.signed_up_again && (
                <div className="events-sub" data-signed-up-again>{signedUpAgainText(h.signed_up_again)}</div>
              )}
            </div>
            <div className="events-sub events-hold-reason">
              {HOLD_REASON_LABELS[h.reason] ?? h.reason}
              {h.signed_up_again && !onlySignedUpAgain(h) && <div>{HOLD_REASON_LABELS.signed_up_again}</div>}
            </div>
          </div>
          {affiliateHoldWarning(h) && (
            <div className="alert alert-warning events-hold-warning" role="note" data-affiliate-warning>
              <AlertTriangle size={15} /><div>{affiliateHoldWarning(h)}</div>
            </div>
          )}
          {h.candidates.length > 0 && !onlySignedUpAgain(h) && (
            <div className="table-wrap">
              <table className="events-hold-table">
                <thead><tr><th>May be</th><th>Contact</th><th>Same</th><th></th></tr></thead>
                <tbody>{h.candidates.map(c => (
                  <tr key={c.customer_id}>
                    <td>
                      <div style={{ fontWeight: 600 }}>{c.full_name}</div>
                      {candidateMergedText(c) && <div className="events-sub" data-candidate-merged>{candidateMergedText(c)}</div>}
                      {c.guest && <div className="events-sub" data-candidate-guest>{candidateGuestText(c)}</div>}
                      {doubleVipWarning(h, c) && (
                        <div className="events-sub events-text-danger" data-double-vip-note>{doubleVipWarning(h, c)}</div>
                      )}
                    </td>
                    <td className="events-sub" style={{ overflowWrap: 'anywhere' }}>{[c.phone, c.email].filter(Boolean).join(' · ') || '—'}</td>
                    <td>
                      {c.phone_matches && <span className="badge badge-success">Phone</span>}{' '}
                      {c.email_matches && <span className="badge badge-success">Email</span>}{' '}
                      {c.name_matches && <span className="badge badge-success">Name</span>}
                    </td>
                    <td style={{ textAlign: 'right' }}>
                      <button className="btn btn-primary btn-sm" data-attach={c.customer_id}
                        onClick={() => open({ kind: 'attach', hold: h, customer: c })}><Link2 size={12} /> Attach</button>
                    </td>
                  </tr>
                ))}</tbody>
              </table>
            </div>
          )}
          <div className="events-actions" style={{ marginTop: 8 }}>
            {h.signed_up_again && h.guest_id && (
              <button className="btn btn-primary btn-sm" data-put-back={h.person_id}
                onClick={() => open({ kind: 'put_back', hold: h })}><RotateCcw size={12} /> Put back on the list</button>
            )}
            {!onlySignedUpAgain(h) && (
              <>
                <button className="btn btn-secondary btn-sm" data-other={h.person_id}
                  onClick={() => open({ kind: 'attach', hold: h, customer: null })}><Link2 size={12} /> Find another customer…</button>
                <button className="btn btn-secondary btn-sm" data-create={h.person_id}
                  onClick={() => open({ kind: 'create', hold: h })}><UserPlus size={12} /> New customer</button>
              </>
            )}
            {canClose && (
              <button className="btn btn-secondary btn-sm" data-close={h.person_id}
                onClick={() => open({ kind: 'close', hold: h })}><XCircle size={12} /> Close</button>
            )}
          </div>
        </div>
      ))}

      {action && (
        <Modal
          title={action.kind === 'attach' ? `Link ${action.hold.full_name}`
            : action.kind === 'create' ? `New customer: ${action.hold.full_name}`
            : action.kind === 'put_back' ? `Put ${action.hold.full_name} back on the list`
            : onlySignedUpAgain(action.hold) ? `Leave ${action.hold.full_name} off the list`
            : `Close ${action.hold.full_name}'s registration`}
          maxWidth={520} onClose={close} confirmClose={note.trim() !== '' || !!otherId}
          footer={<>
            <button className="btn btn-secondary" onClick={close} disabled={busy}>Cancel</button>
            <button className="btn btn-primary" data-confirm onClick={() => void confirm()} disabled={busy || !ready}>
              {busy ? 'Saving…' : action.kind === 'attach' ? 'Link' : action.kind === 'create' ? 'Make customer'
                : action.kind === 'put_back' ? 'Put back' : onlySignedUpAgain(action.hold) ? 'Close' : 'Close registration'}
            </button>
          </>}>
          <div className="form-grid">
            {err && <div className="alert alert-danger" role="alert" style={{ marginBottom: 0 }}><span>⚠</span><div>{err}</div></div>}
            {action.kind === 'attach' && doubleVipWarning(action.hold, linkTo) && (
              <div className="alert alert-warning" role="alert" style={{ marginBottom: 0 }} data-double-vip-warning>
                <AlertTriangle size={15} /><div>{doubleVipWarning(action.hold, linkTo)}</div>
              </div>
            )}
            {action.kind === 'attach' && action.customer?.guest && (
              <p style={{ margin: 0, fontSize: 13.5 }} data-candidate-guest>{candidateGuestText(action.customer)}.</p>
            )}
            {action.kind === 'attach' && action.customer && (
              <p style={{ margin: 0, fontSize: 13.5 }}>
                <strong>{action.hold.full_name}</strong> is <strong>{action.customer.full_name}</strong>. Their name and phone stay
                as they are; an empty email is filled from the registration. Their referrer is not changed.
              </p>
            )}
            {action.kind === 'attach' && !action.customer && (
              <div className="form-group" style={{ marginBottom: 0 }}>
                <label>Customer</label>
                <CustomerSearchSelect value={otherId} onChange={setOtherId} />
              </div>
            )}
            {action.kind === 'attach' && !action.customer && picked?.guest && (
              <p style={{ margin: 0, fontSize: 13.5 }} data-candidate-guest>{candidateGuestText(picked)}.</p>
            )}
            {action.kind === 'create' && affiliateHoldWarning(action.hold) && (
              <div className="alert alert-warning" role="alert" style={{ marginBottom: 0 }} data-affiliate-warning>
                <AlertTriangle size={15} /><div>{affiliateHoldWarning(action.hold)}</div>
              </div>
            )}
            {action.kind === 'create' && (
              <p style={{ margin: 0, fontSize: 13.5 }}>
                A new customer is made: <strong>{action.hold.full_name}</strong>{action.hold.phone ? `, ${action.hold.phone}` : ''}
                {action.hold.email ? `, ${action.hold.email}` : ''}. Use this when they are not the customer shown, for example
                a family member sharing the phone. Through an affiliate's link, someone on another customer's phone, or on the
                affiliate's own phone or email, becomes the affiliate's referral only once an Owner or Manager checks them, and
                the affiliate earns commission on their VIP only from then. The affiliate is never their own referral, and
                someone made a customer under her name is not referred either.
              </p>
            )}
            {action.kind === 'close' && !onlySignedUpAgain(action.hold) && (
              <p style={{ margin: 0, fontSize: 13.5 }}>
                For a registration that is not a real one (a test, sent twice). They come off the guest list and this list.
              </p>
            )}
            {action.kind === 'close' && onlySignedUpAgain(action.hold) && (
              <p style={{ margin: 0, fontSize: 13.5 }} data-close-signed-up-again>{SIGNED_UP_AGAIN_CLOSE_TEXT}</p>
            )}
            {(action.kind === 'put_back' || action.kind === 'close') && action.hold.signed_up_again && (
              <p style={{ margin: 0, fontSize: 13.5 }} data-signed-up-again>{signedUpAgainText(action.hold.signed_up_again)}</p>
            )}
            {action.kind === 'put_back' && action.hold.signed_up_again && (
              <p style={{ margin: 0, fontSize: 13.5 }} data-put-back-note>{putBackText(action.hold.full_name, action.hold.signed_up_again)}</p>
            )}
            {action.kind === 'close' && action.hold.vip_checkout && (
              <p style={{ margin: 0, fontSize: 13.5 }} data-close-checkout>{vipCheckoutCloseNote(action.hold.vip_checkout)}</p>
            )}
            <div className="form-group" style={{ marginBottom: 0 }}>
              <label>{action.kind === 'close' ? 'Reason' : action.kind === 'attach' ? 'How did you confirm it is them?' : 'Note (optional)'}</label>
              <textarea rows={2} value={note} onChange={e => setNote(e.target.value)} aria-label="Note"
                placeholder={action.kind === 'close' ? (onlySignedUpAgain(action.hold) ? 'e.g. Asked not to come' : 'e.g. A test registration')
                  : action.kind === 'attach' ? 'e.g. Asked at the door, same birthday'
                  : action.kind === 'put_back' ? 'e.g. Called her: she can come' : ''} />
            </div>
          </div>
        </Modal>
      )}
    </div>
  );
};

export default RegistrationHoldsPanel;
