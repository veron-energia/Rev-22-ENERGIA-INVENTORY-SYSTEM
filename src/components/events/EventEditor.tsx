import React, { useMemo, useState } from 'react';
import { Plus, Trash2 } from 'lucide-react';
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
 */

interface DayForm { key: string; day: string; capacity: string; registered: number; existing: boolean; }
interface OptionForm {
  key: string; id: string | null; name: string; days_count: string; price: string;
  is_active: boolean; sort_order: string; sold: boolean;
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
      days: [{ key: nextKey(), day: '', capacity: '', registered: 0, existing: false }],
      store_ids: stores.length === 1 ? [stores[0].id] : [],
      options: [{ key: nextKey(), id: null, name: '', days_count: '1', price: '', is_active: true, sort_order: '1', sold: false }],
      early_bird: false, early_bird_until: '', early_bird_percent: '',
      is_active: true, notes: '',
    };
  }
  return {
    name: event.name, description: event.description ?? '',
    daily_start: event.daily_start ?? '', daily_end: event.daily_end ?? '',
    days: event.days.map(d => ({
      key: nextKey(), day: d.day, capacity: d.capacity == null ? '' : String(d.capacity),
      registered: d.registered, existing: true,
    })),
    store_ids: event.stores.map(s => s.id),
    options: event.options.map(o => ({
      key: nextKey(), id: o.id, name: o.name, days_count: String(o.days_count), price: String(o.price),
      is_active: o.is_active, sort_order: String(o.sort_order), sold: o.sold,
    })),
    early_bird: !!event.early_bird_until,
    early_bird_until: event.early_bird_until ?? '',
    early_bird_percent: event.early_bird_percent == null ? '' : String(event.early_bird_percent),
    is_active: event.is_active, notes: event.notes ?? '',
  };
}

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
    }
  });
  const names = f.options.map(o => o.name.trim().toLowerCase()).filter(Boolean);
  if (new Set(names).size !== names.length) errs.push('Two ticket options have the same name.');
  if (f.early_bird) {
    if (!f.early_bird_until) errs.push('Choose the early bird\'s last day.');
    const p = Number(f.early_bird_percent);
    if (f.early_bird_percent.trim() === '' || !Number.isFinite(p) || p <= 0 || p > 100) {
      errs.push('The early-bird discount must be more than 0% and at most 100%.');
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

export const EventEditor: React.FC<{
  event: EventRow | null;
  stores: StoreOption[];
  storesError?: string | null;
  onClose: () => void;
  onSaved: (id: string) => void;
}> = ({ event, stores, storesError, onClose, onSaved }) => {
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

  const addDay = () => setForm(f => {
    const last = [...f.days].map(d => d.day).filter(Boolean).sort().pop();
    return { ...f, days: [...f.days, { key: nextKey(), day: last ? addDays(last, 1) : '', capacity: '', registered: 0, existing: false }] };
  });
  const addOption = () => setForm(f => ({
    ...f,
    options: [...f.options, {
      key: nextKey(), id: null, name: '', days_count: String(Math.max(f.days.length, 1)), price: '',
      is_active: true, sort_order: String(f.options.length + 1), sold: false,
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
              const locked = d.existing && d.registered > 0;
              return (
                <div key={d.key}>
                  <div className="events-day-row">
                    <input type="date" aria-label="Day" value={d.day} readOnly={locked}
                      title={locked ? 'People are registered for this day, so its date cannot change' : undefined}
                      onChange={e => setDay(d.key, { day: e.target.value })} />
                    <input type="number" min={1} step={1} aria-label="Capacity" placeholder="No limit"
                      value={d.capacity} onChange={e => setDay(d.key, { capacity: e.target.value })} />
                    <button type="button" className="btn btn-secondary btn-sm btn-icon" aria-label="Remove day"
                      disabled={locked || form.days.length === 1}
                      title={locked ? 'People are registered for this day, so it cannot be removed' : 'Remove this day'}
                      onClick={() => setForm(f => ({ ...f, days: f.days.filter(x => x.key !== d.key) }))}>
                      <Trash2 size={13} />
                    </button>
                  </div>
                  <div className="events-sub">
                    {d.day ? fmtWeekday(d.day) : 'Choose a date'}
                    {d.existing && d.registered > 0 ? ` · ${d.registered} registered, so this day stays` : ''}
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
                <label key={s.id} className="events-inline">
                  <input type="checkbox" checked={form.store_ids.includes(s.id)}
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
                <div className="events-option-row">
                  <input aria-label="Option name" value={o.name} placeholder="e.g. 1 Day"
                    onChange={e => setOption(o.key, { name: e.target.value })} />
                  <select aria-label="Days covered" value={o.days_count} disabled={o.sold}
                    title={o.sold ? 'Sold already, so the days it covers cannot change. Add a new option instead.' : undefined}
                    onChange={e => setOption(o.key, { days_count: e.target.value })}>
                    {Array.from({ length: Math.max(nDays, Number(o.days_count) || 1) }, (_, i) => i + 1).map(n => (
                      <option key={n} value={String(n)}>{n} day{n === 1 ? '' : 's'}</option>
                    ))}
                  </select>
                  <input aria-label="Price" type="number" min={0} step="0.01" value={o.price}
                    onChange={e => setOption(o.key, { price: e.target.value })} />
                  <label className="events-inline">
                    <input type="checkbox" aria-label="On sale" checked={o.is_active}
                      onChange={e => setOption(o.key, { is_active: e.target.checked })} />
                    On sale
                  </label>
                  <input aria-label="Order" type="number" step={1} value={o.sort_order}
                    onChange={e => setOption(o.key, { sort_order: e.target.value })} />
                  <button type="button" className="btn btn-secondary btn-sm btn-icon" aria-label="Remove option"
                    disabled={o.sold}
                    title={o.sold ? 'Tickets of this option have been sold, so it cannot be removed. Untick "On sale" instead.' : 'Remove this option'}
                    onClick={() => setForm(f => ({ ...f, options: f.options.filter(x => x.key !== o.key) }))}>
                    <Trash2 size={13} />
                  </button>
                </div>
                {o.sold && (
                  <div className="events-sub">Sold already: it cannot be removed and its days stay. Untick "On sale" to stop selling it.</div>
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

        <label className="events-inline">
          <input type="checkbox" checked={form.is_active} onChange={e => set('is_active', e.target.checked)} />
          Tickets on sale
        </label>

        <div className="form-group">
          <label>Notes</label>
          <textarea rows={2} value={form.notes} onChange={e => set('notes', e.target.value)} />
        </div>
      </div>
    </Modal>
  );
};

export default EventEditor;
