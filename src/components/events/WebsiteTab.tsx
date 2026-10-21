import React, { useCallback, useEffect, useMemo, useState } from 'react';
import { AlertTriangle, ArrowDown, ArrowUp, Copy, Globe, KeyRound, Plus, RefreshCw, Trash2 } from 'lucide-react';
import { supabase } from '../../lib/supabase';
import { Modal, ReasonModal } from '../ui';
import contractText from './eventWebsiteContract.ts?raw';
import {
  EventRow, PLANNING_LIMITS, WEB_ORDER_MODE_BADGE, WEB_ORDER_MODE_LABELS, WebKey, WebOrderMode, WebSettings, WebSettingsView,
  fmtDateTime, fmtDayList, fmtHours, money, normalizeWebSettingsView, testOutcomeText,
} from './model';

/*
 * Event → Website (436): the event's own website. Owners, Admins and Managers
 * see it; what an Owner alone may do (the settings, the keys) the server
 * says with can_manage, and enforces.
 *
 *   * What is not ready yet, and what only needs a look.
 *   * The settings: the event code, Off / Record only / Live, the store and
 *     the person who raises the invoices, the VIP ticket, the vouchers that
 *     come with VIP, the gifts, the payment methods, the customer source, the
 *     sync URL. The venue (Owner, Admin, Manager) on its own.
 *   * Connection: the address, the event code and the website's settings to
 *     paste into Vercel; the contract (the API) and how to call it, to copy.
 *   * Keys: made here, shown once (the app keeps only a hash), revoked here.
 *   * Test mode: what a test key sent, and what a live key would have done.
 *   * The latest requests, to see whether the website is reaching the app.
 *   * 436 round 7 (S4): the talk titles the website asks about ("Which talks
 *     interest you most?"), pre-filled with the suggested list until saved
 *     (Owner, Admin, Manager, as the venue). Answers keep the titles people
 *     chose, so renaming or removing one later changes no answer.
 */

const MODES: WebOrderMode[] = ['off', 'record_only', 'live'];
const MODE_BUTTONS: Record<WebOrderMode, string> = { off: 'Off', record_only: 'Record only', live: 'Live' };
const OUTCOME_LABELS: Record<string, string> = {
  bad_key: 'Bad key', wrong_event: 'Wrong event', request_conflict: 'Request conflict', too_many_requests: 'Too many',
  invalid_request: 'Invalid', too_soon: 'Too soon',
};

type Form = {
  code: string; mode: WebOrderMode; store_id: string; acting_profile_id: string; vip_option_id: string;
  vip_voucher_ids: string[]; gift_product_ids: string[]; hitpay_payment_method_id: string; paynow_payment_method_id: string;
  bank_payment_method_id: string; source_option_id: string; source_details: string; sync_url: string;
};

/** A first code from the event's name: HEALTH-SEMINAR… in capitals, at most 40. */
export function suggestedCode(name: string): string {
  const s = name.toUpperCase().replace(/[^A-Z0-9]+/g, '-').replace(/^-+|-+$/g, '').slice(0, 40).replace(/-+$/, '');
  return s.length >= 3 ? s : 'EVENT-WEBSITE';
}

function formOf(s: WebSettings | null, event: EventRow, view: WebSettingsView): Form {
  return {
    code: s?.code ?? suggestedCode(event.name),
    mode: s?.mode ?? 'off',
    store_id: s?.store_id ?? (view.choices.stores.length === 1 ? view.choices.stores[0].id : ''),
    acting_profile_id: s?.acting_profile_id ?? '',
    vip_option_id: s?.vip_option_id ?? (view.choices.options.length === 1 ? view.choices.options[0].id : ''),
    vip_voucher_ids: s?.vip_voucher_ids ?? [],
    gift_product_ids: s?.gift_product_ids ?? [],
    hitpay_payment_method_id: s?.hitpay_payment_method_id ?? '',
    paynow_payment_method_id: s?.paynow_payment_method_id ?? '',
    bank_payment_method_id: s?.bank_payment_method_id ?? '',
    source_option_id: s?.source_option_id ?? '',
    source_details: s?.source_details ?? '',
    sync_url: s?.sync_url ?? '',
  };
}

/** The address the website calls: the project's, then the function's path. */
export function endpointOf(base: string | undefined | null, path: string): string {
  return `${(base ?? '').replace(/\/+$/, '')}${path}`;
}

export function envBlock(endpoint: string, code: string): string {
  return [
    `ENERGIA_EVENT_API_URL=${endpoint}`,
    `ENERGIA_EVENT_CODE=${code}`,
    'ENERGIA_EVENT_API_KEY=<paste the key here; it is shown once when it is made>',
  ].join('\n');
}

// 436: a module of functions (nothing runs when it is imported); it compiles
// as copied next to the contract (website-tab.test.mjs type-checks it).
export const USAGE_EXAMPLE = `// src/lib/event-api.ts on the website (server side only: the key never reaches a browser)
import {
  callEventApi, newRequestId, withEventApiRetries, type EventApiConfig, type RegisterRequest,
} from './event-api-contract';

const config: EventApiConfig = {
  url: process.env.ENERGIA_EVENT_API_URL!,
  key: process.env.ENERGIA_EVENT_API_KEY!,
  event: process.env.ENERGIA_EVENT_CODE!,
};

// A read: the event as the website shows it (cache it for at most 60 s).
export async function eventInfo() {
  return withEventApiRetries(() => callEventApi(config, 'event_info', {}));
}

// A write: make the request id once (newRequestId()), keep it with the registration,
// and pass the same one on every retry of that registration.
export async function register(registration: RegisterRequest['registration'], requestId: string) {
  return withEventApiRetries(() => callEventApi(config, 'register', { registration }, { requestId }));
}

export { newRequestId };
`;

/** A title as the server keeps it: trimmed, every run of spaces one space. */
const tidyTitle = (t: string) => t.replace(/\s+/g, ' ').trim();
type TalkRow = { id: number; text: string };
let talkRowSeq = 0;
const talkRowsOf = (titles: string[]): TalkRow[] => titles.map(text => ({ id: ++talkRowSeq, text }));

async function copy(text: string): Promise<boolean> {
  try { await navigator.clipboard.writeText(text); return true; } catch { return false; }
}

export const WebsiteTab: React.FC<{ event: EventRow; onChanged?: () => void }> = ({ event, onChanged }) => {
  const [view, setView] = useState<WebSettingsView | null>(null);
  const [loading, setLoading] = useState(true);
  const [err, setErr] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [form, setForm] = useState<Form | null>(null);
  const [saving, setSaving] = useState(false);
  const [confirmLive, setConfirmLive] = useState(false);
  const [venue, setVenue] = useState('');
  const [newKind, setNewKind] = useState<'live' | 'test' | null>(null);
  const [newLabel, setNewLabel] = useState('');
  const [made, setMade] = useState<{ key: string; kind: string; hint: string } | null>(null);
  const [revoking, setRevoking] = useState<WebKey | null>(null);
  const [clearing, setClearing] = useState(false);
  const [talkRows, setTalkRows] = useState<TalkRow[]>([]);
  const [talkConfirm, setTalkConfirm] = useState<'none' | 'suggested' | null>(null);
  const [savingTalks, setSavingTalks] = useState(false);

  // Reloads what the app keeps. Each card's Save resets only its own fields from it, so a venue or talk titles
  // being typed on the other card are not thrown away (the review of round 7); Refresh and the first load reset all.
  const load = useCallback(async (reset: { form?: boolean; venue?: boolean; talks?: boolean } = { form: true, venue: true, talks: true }) => {
    setLoading(true);
    const { data, error } = await supabase.rpc('event_web_settings_get', { p_event_id: event.id });
    setLoading(false);
    if (error) { setErr(error.message); return; }
    const v = normalizeWebSettingsView(data);
    setView(v);
    if (reset.form) setForm(formOf(v.settings, event, v));
    if (reset.venue) setVenue(v.settings?.venue ?? '');
    if (reset.talks) setTalkRows(talkRowsOf(v.talks?.titles ?? []));
  }, [event]);
  useEffect(() => { void load(); }, [load]);

  const endpoint = useMemo(() => endpointOf(import.meta.env?.VITE_SUPABASE_URL as string | undefined, view?.endpoint_path ?? '/functions/v1/event-website'),
    [view?.endpoint_path]);
  if (loading && !view) return <div className="card empty-state"><RefreshCw size={24} className="spin" style={{ opacity: 0.4 }} /></div>;
  if (!view || !form) return err ? <div className="alert alert-danger" role="alert"><span>⚠</span><div>{err}</div></div> : null;

  const can = view.can_manage;
  const s = view.settings;
  const set = <K extends keyof Form>(k: K, v: Form[K]) => setForm(f => (f ? { ...f, [k]: v } : f));
  const toggle = (k: 'vip_voucher_ids' | 'gift_product_ids', id: string) =>
    setForm(f => (f ? { ...f, [k]: f[k].includes(id) ? f[k].filter(x => x !== id) : [...f[k], id] } : f));
  const source = view.choices.sources.find(o => o.id === form.source_option_id);

  const save = async () => {
    setConfirmLive(false); setSaving(true); setErr(null); setNotice(null);
    const { error } = await supabase.rpc('event_web_settings_save', { p_event_id: event.id, p_settings: {
      // The venue is set on its own (below), so a Manager's venue is never overwritten here.
      ...form, code: form.code.trim().toUpperCase(),
      vip_option_id: form.vip_option_id || null, hitpay_payment_method_id: form.hitpay_payment_method_id || null,
      paynow_payment_method_id: form.paynow_payment_method_id || null, bank_payment_method_id: form.bank_payment_method_id || null,
      source_option_id: form.source_option_id || null, source_details: form.source_details.trim() || null,
      sync_url: form.sync_url.trim() || null,
    } });
    setSaving(false);
    if (error) { setErr(error.message); return; }
    setNotice('The website settings are saved.');
    await load({ form: true });
    onChanged?.();
  };
  const trySave = () => { if (form.mode === 'live' && s?.mode !== 'live') setConfirmLive(true); else void save(); };

  const saveVenue = async () => {
    setErr(null); setNotice(null);
    const { error } = await supabase.rpc('event_web_set_venue', { p_event_id: event.id, p_venue: venue.trim() || null });
    if (error) { setErr(error.message); return; }
    setNotice(venue.trim() ? 'The venue is saved: the website shows it.' : 'The venue is cleared: the website shows "Venue to be announced".');
    await load({ venue: true });
  };

  const makeKey = async () => {
    if (!newKind) return;
    setErr(null);
    const { data, error } = await supabase.rpc('event_web_key_create', { p_event_id: event.id, p_kind: newKind, p_label: newLabel.trim() || null });
    setNewKind(null); setNewLabel('');
    if (error) { setErr(error.message); return; }
    const r = (data ?? {}) as { key?: string; kind?: string; key_hint?: string };
    setMade({ key: String(r.key ?? ''), kind: String(r.kind ?? ''), hint: String(r.key_hint ?? '') });
  };
  const closeMade = () => { setMade(null); void load({}); };
  const revoke = async (reason: string): Promise<string | null> => {
    if (!revoking) return null;
    const { error } = await supabase.rpc('event_web_key_revoke', { p_key_id: revoking.id, p_reason: reason });
    if (error) return error.message;
    setNotice(`The key ${revoking.key_hint} is revoked: the website using it is refused from now on.`);
    await load({});
    return null;
  };
  const clearTests = async () => {
    setClearing(false); setErr(null);
    const { data, error } = await supabase.rpc('event_web_test_clear', { p_event_id: event.id });
    if (error) { setErr(error.message); return; }
    const r = (data ?? {}) as { registrations?: number; orders?: number; requests?: number };
    setNotice(`Test data cleared: ${r.registrations ?? 0} registration(s), ${r.orders ?? 0} VIP order(s), ${r.requests ?? 0} request(s).`);
    await load({});
  };
  // 436 round 7: the talk titles. null goes back to the suggested list; [] asks about no talks.
  const saveTalks = async (titles: string[] | null) => {
    setTalkConfirm(null); setSavingTalks(true); setErr(null); setNotice(null);
    const { error } = await supabase.rpc('event_web_set_talks', { p_event_id: event.id, p_titles: titles });
    setSavingTalks(false);
    if (error) { setErr(error.message); return; }
    setNotice(titles === null
      ? 'The talk titles are back to the suggested list: the website shows them within a minute.'
      : 'The talk titles are saved: the website shows them within a minute.');
    await load({ talks: true });
    onChanged?.();
  };
  const trySaveTalks = () => {
    const titles = talkRows.map(r => tidyTitle(r.text)).filter(Boolean);
    const seen = new Set<string>();
    for (const t of titles) {
      if (seen.has(t.toLowerCase())) { setErr(`Each talk title only once: ${t}`); return; }
      seen.add(t.toLowerCase());
    }
    if (titles.length > PLANNING_LIMITS.talks) { setErr(`At most ${PLANNING_LIMITS.talks} talk titles`); return; }
    if (titles.length === 0) { setTalkConfirm('none'); return; }
    void saveTalks(titles);
  };
  const moveTalk = (i: number, by: number) => setTalkRows(rows => {
    const j = i + by;
    if (j < 0 || j >= rows.length) return rows;
    const next = [...rows];
    [next[i], next[j]] = [next[j], next[i]];
    return next;
  });

  const copyShown = async (what: string, text: string) => {
    setNotice(await copy(text) ? `${what} copied.` : `Copy ${what.toLowerCase()} by hand: select it and copy.`);
  };

  const keys = view.keys;
  const liveKeys = keys.filter(k => k.kind === 'live' && !k.revoked_at);
  const testKeys = keys.filter(k => k.kind === 'test' && !k.revoked_at);
  const code = s?.code ?? form.code;

  return (
    <div className="events-website" data-website-tab>
      {err && <div className="alert alert-danger" role="alert"><span>⚠</span><div>{err}</div></div>}
      {notice && (
        <div className="alert alert-info" role="status"><span>✓</span><div style={{ flex: 1, overflowWrap: 'anywhere' }}>{notice}</div>
          <button className="btn btn-secondary btn-sm" onClick={() => setNotice(null)}>Dismiss</button></div>
      )}

      {(view.readiness.errors.length > 0 || view.readiness.warnings.length > 0) && (
        <div className="card events-web-readiness" data-readiness>
          {view.readiness.errors.length > 0 && (
            <div className="events-web-ready-errors">
              <strong><AlertTriangle size={14} /> Not ready</strong>
              <ul>{view.readiness.errors.map((e, i) => <li key={i}>{e}</li>)}</ul>
            </div>
          )}
          {view.readiness.warnings.length > 0 && (
            <div className="events-web-ready-warnings">
              <strong>To check</strong>
              <ul>{view.readiness.warnings.map((w, i) => <li key={i}>{w}</li>)}</ul>
            </div>
          )}
        </div>
      )}

      <div className="card events-web-section" data-section="settings">
        <div className="events-head-top">
          <div className="events-web-mode">
            <Globe size={16} /><strong>Website</strong>
            <span className={WEB_ORDER_MODE_BADGE[s?.mode ?? 'off']}>{s ? WEB_ORDER_MODE_LABELS[s.mode] : 'Not set up'}</span>
          </div>
          <button className="btn btn-secondary btn-sm" onClick={() => void load()}><RefreshCw size={13} className={loading ? 'spin' : ''} /> Refresh</button>
        </div>
        {!can && <div className="events-sub">Only an Owner changes these settings and the keys.</div>}
        <fieldset disabled={!can || saving} className="events-web-form">
          <div className="form-grid events-web-grid">
            <div className="form-group">
              <label>Event code</label>
              <input value={form.code} onChange={e => set('code', e.target.value.toUpperCase())} aria-label="Event code" maxLength={40} />
              <div className="events-sub">Capital letters, digits and dashes; the website sends it with every message.</div>
            </div>
            <div className="form-group">
              <label>Mode</label>
              <div className="events-seg" role="group" aria-label="Website mode">
                {MODES.map(m => (
                  <button key={m} type="button" className={`btn btn-sm ${form.mode === m ? 'btn-primary' : 'btn-secondary'}`}
                    aria-pressed={form.mode === m} onClick={() => set('mode', m)}>{MODE_BUTTONS[m]}</button>
                ))}
              </div>
              <div className="events-sub">Off: no registrations or payments. Record only: registrations work, VIP payments are kept without invoices. Live: HitPay VIPs are invoiced at once.</div>
            </div>
            <div className="form-group">
              <label>Store</label>
              <select value={form.store_id} onChange={e => set('store_id', e.target.value)} aria-label="Store">
                <option value="">Choose…</option>
                {view.choices.stores.map(o => <option key={o.id} value={o.id}>{o.name}</option>)}
              </select>
            </div>
            <div className="form-group">
              <label>Invoices raised by</label>
              <select value={form.acting_profile_id} onChange={e => set('acting_profile_id', e.target.value)} aria-label="Invoices raised by">
                <option value="">Choose…</option>
                {view.choices.profiles.map(o => <option key={o.id} value={o.id}>{o.name} ({o.role})</option>)}
              </select>
            </div>
            <div className="form-group">
              <label>VIP ticket</label>
              <select value={form.vip_option_id} onChange={e => set('vip_option_id', e.target.value)} aria-label="VIP ticket">
                <option value="">Choose…</option>
                {view.choices.options.map(o => (
                  <option key={o.id} value={o.id}>{o.name} · {o.days_count} day(s) · {money(o.price)}{o.is_active ? '' : ' · off sale'}</option>
                ))}
              </select>
            </div>
            <div className="form-group">
              <label>HitPay payments</label>
              <select value={form.hitpay_payment_method_id} onChange={e => set('hitpay_payment_method_id', e.target.value)} aria-label="HitPay payment method">
                <option value="">Choose…</option>
                {view.choices.methods.map(o => <option key={o.id} value={o.id}>{o.name}</option>)}
              </select>
            </div>
            <div className="form-group">
              <label>PayNow transfers</label>
              <select value={form.paynow_payment_method_id} onChange={e => set('paynow_payment_method_id', e.target.value)} aria-label="PayNow payment method">
                <option value="">None</option>
                {view.choices.methods.map(o => <option key={o.id} value={o.id}>{o.name}</option>)}
              </select>
            </div>
            <div className="form-group">
              <label>Bank transfers</label>
              <select value={form.bank_payment_method_id} onChange={e => set('bank_payment_method_id', e.target.value)} aria-label="Bank payment method">
                <option value="">None</option>
                {view.choices.methods.map(o => <option key={o.id} value={o.id}>{o.name}</option>)}
              </select>
            </div>
            <div className="form-group">
              <label>New customers' source</label>
              <select value={form.source_option_id} onChange={e => set('source_option_id', e.target.value)} aria-label="Customer source">
                <option value="">None</option>
                {view.choices.sources.map(o => <option key={o.id} value={o.id}>{o.name}</option>)}
              </select>
            </div>
            <div className="form-group">
              <label>Source details{source?.requires_details ? ' *' : ''}</label>
              <input value={form.source_details} onChange={e => set('source_details', e.target.value)} aria-label="Source details"
                placeholder="e.g. Free Two Day Health Seminar (website)" />
            </div>
            <div className="form-group events-web-wide-field">
              <label>Sync URL</label>
              <input value={form.sync_url} onChange={e => set('sync_url', e.target.value)} aria-label="Sync URL"
                placeholder="https://healthtalk-rev22energia.vercel.app/api/app/sync" />
              <div className="events-sub">The app nudges the website here every 10 minutes to update its sheet; its address is also the VIP links' site.</div>
            </div>
          </div>
          <div className="form-group">
            <label>Vouchers that come with VIP (free on each VIP's invoice)</label>
            <div className="events-web-checks">
              {view.choices.vouchers.map(v => (
                <label key={v.id} className="events-inline">
                  <input type="checkbox" checked={form.vip_voucher_ids.includes(v.id)} onChange={() => toggle('vip_voucher_ids', v.id)} />
                  {v.name} <span className="events-sub">({v.code}){form.vip_voucher_ids.includes(v.id) && !v.priced_at_store ? ' · no price at the store yet' : ''}</span>
                </label>
              ))}
            </div>
          </div>
          <div className="form-group">
            <label>Gifts at the door (one per VIP)</label>
            <div className="events-web-checks">
              {view.choices.products.map(p => (
                <label key={p.id} className="events-inline">
                  <input type="checkbox" checked={form.gift_product_ids.includes(p.id)} onChange={() => toggle('gift_product_ids', p.id)} />
                  {p.name} <span className="events-sub">{p.stock != null ? `(${p.stock} at the store)` : ''}</span>
                </label>
              ))}
            </div>
          </div>
          {can && (
            <div className="events-actions">
              <button type="button" className="btn btn-primary" onClick={trySave} disabled={saving}>{saving ? 'Saving…' : 'Save settings'}</button>
            </div>
          )}
        </fieldset>
        <div className="form-group events-web-venue" style={{ marginTop: 12 }}>
          <label>Venue</label>
          <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap' }}>
            <input value={venue} onChange={e => setVenue(e.target.value)} aria-label="Venue" maxLength={300} style={{ flex: '1 1 260px' }}
              disabled={!view.can_set_venue || !s} placeholder="Venue to be announced" />
            {view.can_set_venue && s && <button type="button" className="btn btn-secondary" onClick={() => void saveVenue()}>Save venue</button>}
          </div>
          <div className="events-sub">Until it is set the website shows "Venue to be announced". Type it into the reminder emails too.</div>
        </div>
        {/* The days and hours come from the event itself (Edit event); the website shows them as they are here. */}
        <div className="events-sub" data-hours style={{ marginTop: 8 }}>
          The website shows the event's days and hours: {fmtDayList(event.days.map(d => d.day))}
          {fmtHours(event.daily_start, event.daily_end) ? `, ${fmtHours(event.daily_start, event.daily_end)}` : ', no hours set'}. Change them with Edit event.
        </div>
      </div>

      {view.talks && (
        <div className="card events-web-section events-talks-editor" data-section="talks">
          <div className="events-web-mode">
            <strong>Talk titles</strong>
            {view.talks.saved
              ? <span className="badge badge-success" data-talks-state="saved">Saved</span>
              : <span className="badge badge-accent" data-talks-state="suggested">Suggested list (not saved yet)</span>}
          </div>
          <div className="events-sub">
            The website asks “Which talks interest you most?” with these titles, in this order. Until they are saved it uses
            the suggested list.
          </div>
          {!view.can_set_talks && (
            <div className="events-sub" data-talks-who>
              {s || !view.can_set_venue ? 'Owners, Admins and Managers set the talk titles.' : 'Save the website settings first.'}
            </div>
          )}
          {talkRows.length === 0 && <div className="events-sub" data-talks-none>No titles: the website does not ask about talks.</div>}
          <div className="events-talk-rows">
            {talkRows.map((r, i) => (
              <div key={r.id} className="events-talk-row" data-talk-row>
                <input aria-label={`Talk title ${i + 1}`} maxLength={PLANNING_LIMITS.talk_title} value={r.text}
                  disabled={!view.can_set_talks || savingTalks}
                  onChange={e => { const v = e.target.value; setTalkRows(rows => rows.map(x => (x.id === r.id ? { ...x, text: v } : x))); }} />
                {view.can_set_talks && (
                  <>
                    <button type="button" className="btn btn-secondary btn-sm btn-icon" aria-label={`Move talk title ${i + 1} up`} title="Up"
                      disabled={i === 0 || savingTalks} onClick={() => moveTalk(i, -1)}><ArrowUp size={13} /></button>
                    <button type="button" className="btn btn-secondary btn-sm btn-icon" aria-label={`Move talk title ${i + 1} down`} title="Down"
                      disabled={i === talkRows.length - 1 || savingTalks} onClick={() => moveTalk(i, 1)}><ArrowDown size={13} /></button>
                    <button type="button" className="btn btn-secondary btn-sm" disabled={savingTalks}
                      onClick={() => setTalkRows(rows => rows.filter(x => x.id !== r.id))}>Remove</button>
                  </>
                )}
              </div>
            ))}
          </div>
          {view.can_set_talks && (
            <div className="events-actions events-talks-actions">
              <button type="button" className="btn btn-secondary btn-sm" disabled={talkRows.length >= PLANNING_LIMITS.talks || savingTalks}
                title={talkRows.length >= PLANNING_LIMITS.talks ? `At most ${PLANNING_LIMITS.talks} titles` : undefined}
                onClick={() => setTalkRows(rows => [...rows, ...talkRowsOf([''])])}><Plus size={13} /> Add a title</button>
              {view.talks.saved && (
                <button type="button" className="btn btn-secondary btn-sm" disabled={savingTalks}
                  onClick={() => setTalkConfirm('suggested')}>Use the suggested list</button>
              )}
              <button type="button" className="btn btn-primary btn-sm" disabled={savingTalks} onClick={trySaveTalks}>
                {savingTalks ? 'Saving…' : 'Save talk titles'}
              </button>
            </div>
          )}
          <div className="events-sub">
            People's answers keep the titles they chose: renaming or removing a title later does not change them (the
            Planning tab lists those as “no longer listed”).
          </div>
        </div>
      )}

      <div className="card events-web-section" data-section="connection">
        <strong>Connection</strong>
        <div className="events-web-copy-row">
          <span className="events-sub">Address</span><code data-endpoint>{endpoint}</code>
          <button type="button" className="btn btn-secondary btn-sm" onClick={() => void copyShown('The address', endpoint)}><Copy size={12} /> Copy</button>
        </div>
        <div className="events-web-copy-row">
          <span className="events-sub">Event code</span><code data-code>{code}</code>
          <button type="button" className="btn btn-secondary btn-sm" onClick={() => void copyShown('The event code', code)}><Copy size={12} /> Copy</button>
        </div>
        <div className="events-sub" style={{ marginTop: 8 }}>The website's server settings (Vercel, Environment variables):</div>
        <pre className="events-web-code" data-env>{envBlock(endpoint, code)}</pre>
        <button type="button" className="btn btn-secondary btn-sm" onClick={() => void copyShown('The settings', envBlock(endpoint, code))}><Copy size={12} /> Copy settings</button>
        <details className="events-web-details">
          <summary>The contract (the API, in TypeScript) and how to call it</summary>
          <div className="events-sub">Copy the contract into the website as src/lib/event-api-contract.ts, unchanged.</div>
          <button type="button" className="btn btn-secondary btn-sm" onClick={() => void copyShown('The contract', contractText)}><Copy size={12} /> Copy contract</button>
          <pre className="events-web-code" data-contract>{contractText}</pre>
          <button type="button" className="btn btn-secondary btn-sm" onClick={() => void copyShown('The example', USAGE_EXAMPLE)}><Copy size={12} /> Copy example</button>
          <pre className="events-web-code" data-example>{USAGE_EXAMPLE}</pre>
        </details>
      </div>

      <div className="card events-web-section" data-section="keys">
        <div className="events-head-top">
          <strong><KeyRound size={14} /> Keys</strong>
          {can && s && (
            <div className="events-actions">
              <button type="button" className="btn btn-primary btn-sm" onClick={() => setNewKind('live')}>Create live key</button>
              <button type="button" className="btn btn-secondary btn-sm" onClick={() => setNewKind('test')}>Create test key</button>
            </div>
          )}
        </div>
        <div className="events-sub">
          {liveKeys.length} live, {testKeys.length} test in use. A key is shown once when it is made: the app keeps only a fingerprint of it.
          A test key changes nothing (use it with HitPay's sandbox); a live key works for real (with HitPay production).
        </div>
        {keys.length > 0 && (
          <div className="table-wrap">
            <table className="events-web-keys">
              <thead><tr><th>Key</th><th>Kind</th><th>Label</th><th>Made</th><th>Last used</th><th></th></tr></thead>
              <tbody>{keys.map(k => (
                <tr key={k.id} data-key={k.id} className={k.revoked_at ? 'events-row-cancelled' : undefined}>
                  <td><code>{k.key_hint}</code></td>
                  <td><span className={k.kind === 'live' ? 'badge badge-success' : 'badge badge-accent'}>{k.kind === 'live' ? 'Live' : 'Test'}</span></td>
                  <td>{k.label ?? ''}</td>
                  <td className="events-sub">{fmtDateTime(k.created_at)}{k.created_by_name ? ` · ${k.created_by_name}` : ''}</td>
                  <td className="events-sub">{k.last_used_at ? fmtDateTime(k.last_used_at) : 'Never'}</td>
                  <td>
                    {k.revoked_at
                      ? <span className="events-sub">Revoked {fmtDateTime(k.revoked_at)}{k.revoked_reason ? `: ${k.revoked_reason}` : ''}</span>
                      : can && <button type="button" className="btn btn-secondary btn-sm" onClick={() => setRevoking(k)}><Trash2 size={12} /> Revoke</button>}
                  </td>
                </tr>
              ))}</tbody>
            </table>
          </div>
        )}
      </div>

      <div className="card events-web-section" data-section="test">
        <div className="events-head-top">
          <strong>Test mode</strong>
          {view.can_clear_tests && (view.test.registrations.length > 0 || view.test.orders.length > 0) && (
            <button type="button" className="btn btn-secondary btn-sm" onClick={() => setClearing(true)}>Clear test data</button>
          )}
        </div>
        <div className="events-sub">
          {testKeys.length ? 'A test key is in use.' : 'No test key in use.'} What the website sent with a test key: nothing reached customers,
          the guest list, invoices or stock. A test key's planning answers are checked and never kept.
        </div>
        {view.test.registrations.length === 0 && view.test.orders.length === 0
          ? <div className="events-sub" style={{ marginTop: 6 }}>Nothing yet.</div>
          : (
            <ul className="events-web-tests">
              {view.test.registrations.map(r => (
                <li key={r.registration_id} data-test-registration={r.registration_id}>
                  <strong>{r.registration_id}</strong>{r.referral_code ? ` · link ${r.referral_code}` : ''}
                  <ul>{r.people.map(p => (
                    <li key={p.person_id}>{p.full_name} · {p.days.join(', ')}{p.vip !== 'none' ? ` · VIP ${p.vip}` : ''}
                      {p.test_outcome && <div className="events-sub">{testOutcomeText(p.test_outcome)}</div>}
                      {p.referral_note && <div className="events-sub" data-referral-note>{p.referral_note}</div>}</li>
                  ))}</ul>
                </li>
              ))}
              {view.test.orders.map(o => (
                <li key={o.id} data-test-order={o.order_id}>
                  <strong>{o.order_id}</strong> · {o.provider} · {money(o.amount_paid ?? o.amount_total)} · {o.status}
                  {o.test_note && <div className="events-sub">{o.test_note}</div>}
                  {o.review_reason && <div className="events-sub">{o.review_reason}</div>}
                </li>
              ))}
            </ul>
          )}
      </div>

      <div className="card events-web-section" data-section="requests">
        <strong>Latest requests</strong>
        {view.requests.length === 0
          ? <div className="events-sub">The website has not called yet.</div>
          : (
            <div className="table-wrap">
              <table className="events-web-requests">
                <thead><tr><th>When</th><th>Message</th><th>Key</th><th>Outcome</th></tr></thead>
                <tbody>{view.requests.map((r, i) => (
                  <tr key={i}>
                    <td className="events-sub">{fmtDateTime(r.received_at)}</td>
                    <td>{r.type}</td>
                    <td>{r.kind === 'live' ? 'Live' : 'Test'}</td>
                    <td>{r.outcome ? (OUTCOME_LABELS[r.outcome] ?? r.outcome) : ''}</td>
                  </tr>
                ))}</tbody>
              </table>
            </div>
          )}
      </div>

      {confirmLive && (
        <Modal title="Switch the website Live?" maxWidth={460} onClose={() => setConfirmLive(false)}
          footer={<>
            <button className="btn btn-secondary" onClick={() => setConfirmLive(false)}>Cancel</button>
            <button className="btn btn-primary" data-confirm onClick={() => void save()}>Switch Live</button>
          </>}>
          <div className="form-grid">
            <div>Every HitPay VIP payment then becomes invoices at once, one per person, raised at the store by the person chosen.</div>
            <div className="events-sub">Use the live key with HitPay production; keep the test key for HitPay's sandbox.</div>
          </div>
        </Modal>
      )}
      {newKind && (
        <Modal title={`Create a ${newKind} key`} maxWidth={440} onClose={() => setNewKind(null)}
          footer={<>
            <button className="btn btn-secondary" onClick={() => setNewKind(null)}>Cancel</button>
            <button className="btn btn-primary" data-confirm onClick={() => void makeKey()}>Create key</button>
          </>}>
          <div className="form-group" style={{ marginBottom: 0 }}>
            <label>Label (optional)</label>
            <input value={newLabel} onChange={e => setNewLabel(e.target.value)} aria-label="Key label"
              placeholder={newKind === 'live' ? 'e.g. Vercel production' : 'e.g. Vercel preview'} />
          </div>
        </Modal>
      )}
      {made && (
        <Modal title={`Your new ${made.kind} key`} maxWidth={560} onClose={closeMade}
          footer={<button className="btn btn-primary" data-copied onClick={closeMade}>I have copied it</button>}>
          <div className="form-grid">
            <div className="alert alert-warning" style={{ marginBottom: 0 }}><span>⚠</span>
              <div>It is shown only now. Paste it into the website's server settings as ENERGIA_EVENT_API_KEY. The app keeps only a
                fingerprint of it, so it cannot show it again; if it is lost, make a new one and revoke this one ({made.hint}).</div></div>
            <input readOnly value={made.key} aria-label="The new key" data-new-key onFocus={e => e.currentTarget.select()} />
            <button type="button" className="btn btn-secondary" onClick={() => void copyShown('The key', made.key)}><Copy size={13} /> Copy key</button>
          </div>
        </Modal>
      )}
      {revoking && (
        <ReasonModal title={`Revoke ${revoking.key_hint}`} label="Why is it revoked?" confirmLabel="Revoke key" minLength={3}
          placeholder="e.g. Testing finished, or shared by mistake" onClose={() => setRevoking(null)} onSubmitAsync={revoke} />
      )}
      {talkConfirm && (
        <Modal title={talkConfirm === 'none' ? 'Save with no titles?' : 'Go back to the suggested list?'} maxWidth={460}
          onClose={() => setTalkConfirm(null)}
          footer={<>
            <button className="btn btn-secondary" onClick={() => setTalkConfirm(null)}>Cancel</button>
            <button className="btn btn-primary" data-confirm
              onClick={() => void saveTalks(talkConfirm === 'none' ? [] : null)}>
              {talkConfirm === 'none' ? 'Save with no titles' : 'Use the suggested list'}
            </button>
          </>}>
          <div data-talks-confirm>
            {talkConfirm === 'none'
              ? 'Save with no titles? The website then does not ask about talks.'
              : 'Go back to the suggested list? Answers already given keep the titles people chose.'}
          </div>
        </Modal>
      )}
      {clearing && (
        <Modal title="Clear the test data?" maxWidth={440} onClose={() => setClearing(false)}
          footer={<>
            <button className="btn btn-secondary" onClick={() => setClearing(false)}>Cancel</button>
            <button className="btn btn-danger" data-confirm onClick={() => void clearTests()}>Clear test data</button>
          </>}>
          <div>The test registrations, test VIP orders and the test key's requests are deleted. A real payment that reached the test key stays.</div>
        </Modal>
      )}
    </div>
  );
};

export default WebsiteTab;
