import React, { useMemo, useState } from 'react';
import { AlertTriangle, Plus, Trash2 } from 'lucide-react';
import { supabase } from '../../lib/supabase';
import { Modal } from '../ui';
import {
  EventRow, StoreOption, earlyBirdPrice, fmtDate, fmtWeekday, money,
} from './model';

/*
 * Creates or changes an event: its days (each with an optional capacity), the
 * stores it is held at, its ticket options and an optional early bird. Only
 * the obvious is checked here; the server checks everything again and its
 * message is shown as it is.
 *
 * 415: a day stays while people are registered for it or a ticket on an
 * invoice that is not deleted covers it; an option's days stay while it is on
 * such an invoice, and the option itself while it is on any invoice. Order is
 * a whole number, prices are in dollars and cents, and a store the person does
 * not work at cannot be taken off (the server keeps it). While the event's
 * website channel sells, taking a ticket off sale here warns that the website
 * still sells it.
 */

interface DayForm {
  key: string; day: string; capacity: string; registered: number; ticket_lines: number; existing: boolean;
}
interface OptionForm {
  key: string; id: string | null; name: string; days_count: string; price: string;
  is_active: boolean; sort_order: string; sold: boolean; on_any_invoice: boolean;
}
interface EditorForm {
  name: string; description: string; daily_start: string; daily_end: string;
  days: DayForm[]; store_ids: string[]; options: OptionForm[];
  early_bird: boolean; early_bird_until: string; early_bird_percent: string;
  is_active: boolean; notes: string;
}

let keySeq = 0;
const nextKey = () => `k${++keySeq}`;

function addDays(day: string, n: number): string {
  const [y, m, d] = day.split('-').map(Number);
  const dt = new Date(Date.UTC(y, m - 1, d + n));
  return dt.toISOString().slice(0, 10);
}

function initialForm(event: EventRow | null, stores: StoreOption[]): EditorForm {
  if (!event) {
    return {
      name: '', description: '', daily_start: '', daily_end: '',
      days: [{ key: nextKey(), day: '', capacity: '', registered: 0, ticket_lines: 0, existing: false }],
      store_ids: stores.length === 1 ? [stores[0].id] : [],
      options: [{
        key: nextKey(), id: null, name: '', days_count: '1', price: '', is_active: true, sort_order: '1',
        sold: false, on_any_invoice: false,
      }],
      early_bird: false, early_bird_until: '', early_bird_percent: '',
      is_active: true, notes: '',
    };
  }
  return {
    name: event.name, description: event.description ?? '',
    daily_start: event.daily_start ?? '', daily_end: event.daily_end ?? '',
    days: event.days.map(d => ({
      key: nextKey(), day: d.day, capacity: d.capacity == null ? '' : String(d.capacity),
      registered: d.registered, ticket_lines: d.ticket_lines, existing: true,
    })),
    store_ids: event.stores.map(s => s.id),
    options: event.options.map(o => ({
      key: nextKey(), id: o.id, name: o.name, days_count: String(o.days_count), price: String(o.price),
      is_active: o.is_active, sort_order: String(o.sort_order), sold: o.sold, on_any_invoice: o.on_any_invoice,
    })),
    early_bird: !!event.early_bird_until,
    early_bird_until: event.early_bird_until ?? '',
    early_bird_percent: event.early_bird_percent == null ? '' : String(event.early_bird_percent),
    is_active: event.is_active, notes: event.notes ?? '',
  };
}

/** A whole number, written as one ("2", "-1"; not "1.5" or "2.0"). */
export const isWholeNumber = (v: string) => /^-?\d+$/.test(v.trim());
/** At most two decimals, as money and the stored percent are kept. */
export const hasAtMostTwoDecimals = (v: string) => /^-?\d*(\.\d{0,2})?$/.test(v.trim());

function validate(f: EditorForm): string[] {
  const errs: string[] = [];
  if (!f.name.trim()) errs.push('Give the event a name.');
  const days = f.days.map(d => d.day);
  if (days.length === 0) errs.push('Give the event at least one day.');
  if (days.some(d => !d)) errs.push('Every event day needs a date.');
  if (new Set(days.filter(Boolean)).size !== days.filter(Boolean).length) errs.push('A day is listed twice.');
  if (f.days.some(d => d.capacity.trim() !== '' && !(Number.isInteger(Number(d.capacity)) && Number(d.capacity) > 0))) {
    errs.push('A day\'s capacity must be a whole number more than zero, or left empty for no limit.');
  }
  if (f.daily_start && f.daily_end && f.daily_end <= f.daily_start) errs.push('The daily end time must be after the start time.');
  if (f.store_ids.length === 0) errs.push('Choose the store(s) the event is at.');
  if (f.options.length === 0) errs.push('Give the event at least one ticket option.');
  const n = f.days.length;
  f.options.forEach((o, i) => {
    const label = o.name.trim() || `Ticket option ${i + 1}`;
    if (!o.name.trim()) errs.push(`Ticket option ${i + 1} needs a name.`);
    const dc = Number(o.days_count);
    if (!Number.isInteger(dc) || dc < 1 || dc > Math.max(n, 1)) {
      errs.push(`"${label}" must cover between 1 and ${Math.max(n, 1)} day(s).`);
    }
    if (o.price.trim() === '' || !Number.isFinite(Number(o.price)) || Number(o.price) < 0) {
      errs.push(`"${label}" needs a price of zero or more.`);
    } else if (!hasAtMostTwoDecimals(o.price)) {
      errs.push(`Prices are in dollars and cents: "${label}" has more than 2 decimals.`);
    }
    if (o.sort_order.trim() !== '' && !isWholeNumber(o.sort_order)) {
      errs.push(`The order of "${label}" must be a whole number.`);
    }
  });
  const names = f.options.map(o => o.name.trim().toLowerCase()).filter(Boolean);
  if (new Set(names).size !== names.length) errs.push('Two ticket options have the same name.');
  if (f.early_bird) {
    if (!f.early_bird_until) errs.push('Choose the early bird\'s last day.');
    const p = Number(f.early_bird_percent);
    if (f.early_bird_percent.trim() === '' || !Number.isFinite(p) || p <= 0 || p > 100) {
      errs.push('The early-bird discount must be more than 0% and at most 100%.');
    } else if (!hasAtMostTwoDecimals(f.early_bird_percent)) {
      errs.push('The early-bird discount may have at most 2 decimals.');
    }
  }
  return errs;
}

function buildEventPayload(f: EditorForm, id: string | null) {
  const days = [...f.days].sort((a, b) => a.day.localeCompare(b.day));
  return {
    ...(id ? { id } : {}),
    name: f.name.trim(),
    description: f.description.trim() || null,
    daily_start: f.daily_start || null,
    daily_end: f.daily_end || null,
    early_bird_until: f.early_bird ? f.early_bird_until || null : null,
    early_bird_percent: f.early_bird && f.early_bird_percent.trim() !== '' ? Number(f.early_bird_percent) : null,
    is_active: f.is_active,
    notes: f.notes.trim() || null,
    days: days.map(d => ({ day: d.day, capacity: d.capacity.trim() === '' ? null : Number(d.capacity) })),
    store_ids: f.store_ids,
    options: f.options.map((o, i) => ({
      ...(o.id ? { id: o.id } : {}),
      name: o.name.trim(),
      days_count: Number(o.days_count),
      price: Number(o.price),
      is_active: o.is_active,
      sort_order: o.sort_order.trim() === '' ? i + 1 : Number(o.sort_order),
    })),
  };
}

/**
 * 415 (EVENTS-7, the Owner 9 Oct 2026): what the editor says while the event's
 * website sells, when a ticket is taken off sale here. The website asks the
 * inventory before it opens each checkout and reloads its page every minute.
 * A checkout already open (Stripe or HitPay) can still be paid for up to an
 * hour, and such an order is still invoiced.
 */
export const WEBSITE_FOLLOWS_ON_SALE =
  'The website stops offering these within a minute. A checkout already open can still be paid for up to an hour, and is invoiced.';

export const EventEditor: React.FC<{
  event: EventRow | null;
  stores: StoreOption[];
  storesError?: string | null;
  /** Owners and Admins change any store; anyone else only the stores they work at. */
  canChangeAnyStore?: boolean;
  onClose: () => void;
  onSaved: (id: string) => void;
}> = ({ event, stores, storesError, canChangeAnyStore = false, onClose, onSaved }) => {
  const [form, setForm] = useState<EditorForm>(() => initialForm(event, stores));
  const [errors, setErrors] = useState<string[]>([]);
  const [serverErr, setServerErr] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);

  const set = <K extends keyof EditorForm>(k: K, v: EditorForm[K]) => setForm(f => ({ ...f, [k]: v }));
  const setDay = (key: string, patch: Partial<DayForm>) =>
    setForm(f => ({ ...f, days: f.days.map(d => (d.key === key ? { ...d, ...patch } : d)) }));
  const setOption = (key: string, patch: Partial<OptionForm>) =>
    setForm(f => ({ ...f, options: f.options.map(o => (o.key === key ? { ...o, ...patch } : o)) }));

  // Stores the person can pick, plus any the event is already at that are no
  // longer in that list (an inactive store), so saving never drops one silently.
  const storeChoices = useMemo(() => {
    const list = [...stores];
    for (const s of event?.stores ?? []) if (!list.some(x => x.id === s.id)) list.push({ id: s.id, name: `${s.name} (not in your stores)` });
    return list;
  }, [stores, event]);
  // EVENTS-9: the server keeps a store the person does not work at, so such a
  // store cannot be taken off here either.
  const storeLocked = (id: string) => !canChangeAnyStore && !stores.some(s => s.id === id);
  // EVENTS-7: the website follows On sale (415); say so while it sells.
  const websiteSells = event?.web_channel_mode === 'live' || event?.web_channel_mode === 'record_only';

  const addDay = () => setForm(f => {
    const last = [...f.days].map(d => d.day).filter(Boolean).sort().pop();
    return {
      ...f,
      days: [...f.days, { key: nextKey(), day: last ? addDays(last, 1) : '', capacity: '', registered: 0, ticket_lines: 0, existing: false }],
    };
  });
  const addOption = () => setForm(f => ({
    ...f,
    options: [...f.options, {
      key: nextKey(), id: null, name: '', days_count: String(Math.max(f.days.length, 1)), price: '',
      is_active: true, sort_order: String(f.options.length + 1), sold: false, on_any_invoice: false,
    }],
  }));

  const nDays = Math.max(form.days.length, 1);
  const pct = Number(form.early_bird_percent);
  const earlyOn = form.early_bird && !!form.early_bird_until && Number.isFinite(pct) && pct > 0 && pct <= 100;
  const previews = form.options.map(o => {
    const price = Number(o.price);
    const name = o.name.trim() || 'Unnamed option';
    if (o.price.trim() === '' || !Number.isFinite(price)) return `${name}: price not set`;
    const days = Number(o.days_count) || 1;
    const covers = `covers ${days} day${days === 1 ? '' : 's'}`;
    const off = o.is_active ? '' : ' · off sale';
    return earlyOn
      ? `${name}: ${money(price)} (early bird ${money(earlyBirdPrice(price, pct))} until ${fmtDate(form.early_bird_until)}) · ${covers}${off}`
      : `${name}: ${money(price)} · ${covers}${off}`;
  });

  const save = async () => {
    setServerErr(null);
    const errs = validate(form);
    setErrors(errs);
    if (errs.length) return;
    setSaving(true);
    const { data, error } = await supabase.rpc('event_save', { p_event: buildEventPayload(form, event?.id ?? null) });
    setSaving(false);
    if (error) { setServerErr(error.message); return; }
    onSaved(String(data ?? event?.id ?? ''));
  };

  return (
    <Modal title={event ? `Edit ${event.name}` : 'New event'} maxWidth={820} confirmClose onClose={onClose}
      footer={<>
        <button className="btn btn-secondary" onClick={onClose}>Cancel</button>
        <button className="btn btn-primary" onClick={save} disabled={saving}>
          {saving ? 'Saving…' : event ? 'Save changes' : 'Create event'}
        </button>
      </>}>
      <div className="form-grid events-editor">
        {errors.length > 0 && (
          <div className="alert alert-danger" role="alert" style={{ marginBottom: 0 }}>
            <span>⚠</span>
            <div>{errors.length === 1 ? errors[0] : <ul style={{ paddingLeft: 16 }}>{errors.map(e => <li key={e}>{e}</li>)}</ul>}</div>
          </div>
        )}
        {serverErr && <div className="alert alert-danger" role="alert" style={{ marginBottom: 0 }}><span>⚠</span><div>{serverErr}</div></div>}

        <div className="form-group">
          <label>Name *</label>
          <input value={form.name} onChange={e => set('name', e.target.value)} placeholder="e.g. Anniversary Open Days" autoFocus />
        </div>
        <div className="form-group">
          <label>Description</label>
          <textarea rows={2} value={form.description} onChange={e => set('description', e.target.value)} />
        </div>
        <div className="form-grid-2">
          <div className="form-group">
            <label>Daily start</label>
            <input type="time" value={form.daily_start} onChange={e => set('daily_start', e.target.value)} />
          </div>
          <div className="form-group">
            <label>Daily end</label>
            <input type="time" value={form.daily_end} onChange={e => set('daily_end', e.target.value)} />
          </div>
        </div>

        <div>
          <div className="events-section-title">Days *</div>
          <div className="events-rows">
            {form.days.map(d => {
              // A day stays while people are registered for it, or a ticket on
              // an invoice that is not deleted covers it (as the server checks).
              const held = [
                d.registered > 0 ? `${d.registered} registered` : '',
                d.ticket_lines > 0 ? (d.ticket_lines === 1 ? 'a ticket covers it' : `${d.ticket_lines} ticket lines cover it`) : '',
              ].filter(Boolean).join(', ');
              const locked = d.existing && !!held;
              const why = d.registered > 0 ? 'People are registered for this day' : 'Tickets on invoices cover this day';
              return (
                <div key={d.key}>
                  <div className="events-day-row">
                    <input type="date" aria-label="Day" value={d.day} readOnly={locked}
                      title={locked ? `${why}, so its date cannot change` : undefined}
                      onChange={e => setDay(d.key, { day: e.target.value })} />
                    <input type="number" min={1} step={1} aria-label="Capacity" placeholder="No limit"
                      value={d.capacity} onChange={e => setDay(d.key, { capacity: e.target.value })} />
                    <button type="button" className="btn btn-secondary btn-sm btn-icon" aria-label="Remove day"
                      disabled={locked || form.days.length === 1}
                      title={locked ? `${why}, so it cannot be removed` : 'Remove this day'}
                      onClick={() => setForm(f => ({ ...f, days: f.days.filter(x => x.key !== d.key) }))}>
                      <Trash2 size={13} />
                    </button>
                  </div>
                  <div className="events-sub">
                    {d.day ? fmtWeekday(d.day) : 'Choose a date'}
                    {locked ? ` · ${held}, so this day stays` : ''}
                    {d.capacity.trim() === '' ? ' · no capacity limit' : ` · capacity ${d.capacity} people (a full day only warns)`}
                  </div>
                </div>
              );
            })}
          </div>
          <button type="button" className="btn btn-secondary btn-sm" style={{ marginTop: 8 }} onClick={addDay}>
            <Plus size={13} /> Add a day
          </button>
        </div>

        <div>
          <div className="events-section-title">Stores *</div>
          {storesError && <div className="alert alert-danger" style={{ marginBottom: 8 }}><span>⚠</span><div>{storesError}</div></div>}
          {storeChoices.length === 0 ? (
            <div className="events-sub">No stores are available to you.</div>
          ) : (
            <div className="events-store-grid">
              {storeChoices.map(s => (
                <label key={s.id} className="events-inline"
                  title={storeLocked(s.id) ? 'Only someone who works at this store can remove it' : undefined}>
                  <input type="checkbox" checked={form.store_ids.includes(s.id)} disabled={storeLocked(s.id)}
                    onChange={e => set('store_ids', e.target.checked
                      ? [...form.store_ids, s.id] : form.store_ids.filter(x => x !== s.id))} />
                  {s.name}
                </label>
              ))}
            </div>
          )}
          <div className="events-sub" style={{ marginTop: 4 }}>
            Invoices at these stores on an event day count as the event's sales, and their staff run the guest list.
          </div>
        </div>

        <div>
          <div className="events-section-title">Ticket options *</div>
          <div className="events-rows">
            <div className="events-option-row events-option-head">
              <span>Name</span><span>Days covered</span><span>Price (S$)</span><span>On sale</span><span>Order</span><span></span>
            </div>
            {form.options.map(o => (
              <div key={o.key}>
                {/* On a phone the column heads are hidden, so each box carries its own small label (EVENTS-10). */}
                <div className="events-option-row">
                  <label className="events-option-cell">
                    <span className="events-mobile-label">Name</span>
                    <input aria-label="Option name" value={o.name} placeholder="e.g. 1 Day"
                      onChange={e => setOption(o.key, { name: e.target.value })} />
                  </label>
                  <label className="events-option-cell">
                    <span className="events-mobile-label">Days covered</span>
                    <select aria-label="Days covered" value={o.days_count} disabled={o.sold}
                      title={o.sold ? 'Sold already, so the days it covers cannot change. Add a new option instead.' : undefined}
                      onChange={e => setOption(o.key, { days_count: e.target.value })}>
                      {Array.from({ length: Math.max(nDays, Number(o.days_count) || 1) }, (_, i) => i + 1).map(n => (
                        <option key={n} value={String(n)}>{n} day{n === 1 ? '' : 's'}</option>
                      ))}
                    </select>
                  </label>
                  <label className="events-option-cell">
                    <span className="events-mobile-label">Price (S$)</span>
                    <input aria-label="Price" type="number" min={0} step="0.01" value={o.price} placeholder="Price S$"
                      onChange={e => setOption(o.key, { price: e.target.value })} />
                  </label>
                  <label className="events-inline">
                    <input type="checkbox" aria-label="On sale" checked={o.is_active}
                      onChange={e => setOption(o.key, { is_active: e.target.checked })} />
                    On sale
                  </label>
                  <label className="events-option-cell">
                    <span className="events-mobile-label">Order</span>
                    <input aria-label="Order" type="number" step={1} value={o.sort_order} placeholder="Order"
                      onChange={e => setOption(o.key, { sort_order: e.target.value })} />
                  </label>
                  <button type="button" className="btn btn-secondary btn-sm btn-icon" aria-label="Remove option"
                    disabled={o.on_any_invoice}
                    title={o.on_any_invoice ? 'Tickets of this option are on invoices, so it cannot be removed. Untick "On sale" instead.' : 'Remove this option'}
                    onClick={() => setForm(f => ({ ...f, options: f.options.filter(x => x.key !== o.key) }))}>
                    <Trash2 size={13} />
                  </button>
                </div>
                {o.sold ? (
                  <div className="events-sub">Sold already: it cannot be removed and its days stay. Untick "On sale" to stop selling it.</div>
                ) : o.on_any_invoice ? (
                  <div className="events-sub">On a deleted invoice: it cannot be removed, but its days can change. Untick "On sale" to stop selling it.</div>
                ) : null}
                {websiteSells && !o.is_active && (
                  <div className="events-web-sells" role="note"><AlertTriangle size={13} /> {WEBSITE_FOLLOWS_ON_SALE}</div>
                )}
              </div>
            ))}
          </div>
          <button type="button" className="btn btn-secondary btn-sm" style={{ marginTop: 8 }} onClick={addOption}>
            <Plus size={13} /> Add a ticket option
          </button>
        </div>

        <div>
          <label className="events-inline">
            <input type="checkbox" checked={form.early_bird} onChange={e => set('early_bird', e.target.checked)} />
            Early bird price
          </label>
          {form.early_bird && (
            <div className="form-grid-2" style={{ marginTop: 8 }}>
              <div className="form-group">
                <label>Last day of the early bird *</label>
                <input type="date" value={form.early_bird_until} onChange={e => set('early_bird_until', e.target.value)} />
                <small className="events-sub">Invoices dated on or before this day get the early-bird price.</small>
              </div>
              <div className="form-group">
                <label>Discount per person (% off) *</label>
                <input type="number" min={1} max={100} step="0.01" value={form.early_bird_percent}
                  onChange={e => set('early_bird_percent', e.target.value)} />
              </div>
            </div>
          )}
        </div>

        <div className="events-preview" aria-label="Price preview">
          {previews.map((p, i) => <div key={i}>{p}</div>)}
        </div>

        <div>
          <label className="events-inline">
            <input type="checkbox" checked={form.is_active} onChange={e => set('is_active', e.target.checked)} />
            Tickets on sale
          </label>
          {websiteSells && !form.is_active && (
            <div className="events-web-sells" role="note"><AlertTriangle size={13} /> {WEBSITE_FOLLOWS_ON_SALE}</div>
          )}
        </div>

        <div className="form-group">
          <label>Notes</label>
          <textarea rows={2} value={form.notes} onChange={e => set('notes', e.target.value)} />
        </div>
      </div>
    </Modal>
  );
};

export default EventEditor;
