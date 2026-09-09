import React, { useCallback, useEffect, useMemo, useState } from 'react';
import { AlertTriangle, Plus, RefreshCw, Trash2 } from 'lucide-react';
import { supabase } from '../../lib/supabase';
import { inspectPhone } from '../../lib/customer-phones/normalize.mjs';
import './therapy.css';

/**
 * Holiday calendars, company closures, and which customers they affect.
 *
 * Two rules this UI exists to make visible:
 *
 *   * A country's holidays extend only the entitlements assigned to that
 *     country. "All countries" is a separate, explicit choice.
 *   * A year nobody has checked against a source is not a year with no
 *     holidays. Coverage is recorded separately from the dates so an empty
 *     calendar reads as "not configured", never as "nothing to add".
 */

interface Country { code: string; name: string; is_active: boolean; requires_region: boolean; notes: string | null; }
interface Closure {
  id: string; closure_date: string; kind: string; name: string;
  country_code: string | null; region: string | null; observed_for: string | null;
  source: string | null; source_reference: string | null;
}

const fmt = (d: string | null) =>
  !d ? '—' : new Date(`${d}T12:00:00Z`).toLocaleDateString('en-GB',
    { weekday: 'short', day: '2-digit', month: 'short', year: 'numeric', timeZone: 'UTC' });

/**
 * The holiday country suggested by a customer's phone number.
 *
 * A suggestion only. A phone number is not proof of where somebody lives or
 * where they attend, so this fills the field in and says where it came from —
 * it never decides. The parsing is the system's existing one; a second
 * dialling-code table would drift from it.
 */
export function suggestCountryFromPhone(phone: string | null | undefined):
  { country: string | null; why: string } {
  if (!phone || !String(phone).trim()) return { country: null, why: 'No phone number on file.' };
  const seen = inspectPhone(phone);
  if (!seen.country) {
    return { country: null, why: `The phone number could not be resolved to a country (${seen.status}).` };
  }
  return { country: seen.country, why: `Suggested from the phone number (${seen.country}). Confirm before relying on it.` };
}

export const HolidayCountryField: React.FC<{
  countries: Country[]; value: string | null; region: string | null;
  phone?: string | null;
  onChange: (country: string | null, region: string | null) => void;
}> = ({ countries, value, region, phone, onChange }) => {
  const suggestion = useMemo(() => suggestCountryFromPhone(phone), [phone]);
  const country = countries.find(c => c.code === value) ?? null;

  return (
    <div>
      <div className="form-group" style={{ marginBottom: 6 }}>
        <label htmlFor="holiday-country">Holiday country</label>
        <select id="holiday-country" value={value ?? ''}
                onChange={e => onChange(e.target.value || null, null)}>
          <option value="">Not assigned</option>
          {countries.filter(c => c.is_active).map(c => (
            <option key={c.code} value={c.code}>{c.name} ({c.code})</option>
          ))}
        </select>
      </div>

      {!value && (
        <p className="therapy-remaining-hint">
          {suggestion.country
            ? <>Suggested: <strong>{suggestion.country}</strong>. {suggestion.why}{' '}
                <button type="button" className="btn btn-secondary btn-sm"
                        onClick={() => onChange(suggestion.country, null)}>Use it</button></>
            : suggestion.why}
          {' '}Without a country, no holiday calendar applies and the expiry cannot be called verified.
        </p>
      )}

      {country?.requires_region && (
        <div className="form-group" style={{ marginTop: 6 }}>
          <label htmlFor="holiday-region">Region or state (required for {country.name})</label>
          <input id="holiday-region" value={region ?? ''} placeholder="e.g. Selangor"
                 onChange={e => onChange(value, e.target.value || null)} />
          {!region && (
            <p className="therapy-remaining-hint">
              {country.name} holidays vary by region. Until one is chosen, this expiry is
              flagged as needing configuration rather than treated as complete.
            </p>
          )}
        </div>
      )}
    </div>
  );
};

export const HolidayAdmin: React.FC<{ canManage: boolean }> = ({ canManage }) => {
  const [countries, setCountries] = useState<Country[]>([]);
  const [closures, setClosures] = useState<Closure[]>([]);
  const [country, setCountry] = useState<string>('SG');
  const [year, setYear] = useState<number>(new Date().getFullYear());
  const [coverage, setCoverage] = useState<any | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const [form, setForm] = useState({
    date: '', kind: 'public_holiday', name: '', scope: 'SG',
    region: '', observedFor: '', source: '', sourceRef: '', reason: '',
  });

  const load = useCallback(async () => {
    setBusy(true);
    const [{ data: cs, error: ce }, { data: cl, error: le }] = await Promise.all([
      supabase.from('therapy_holiday_countries').select('*').order('name'),
      supabase.from('therapy_closure_dates').select('*').is('deleted_at', null)
        .gte('closure_date', `${year}-01-01`).lte('closure_date', `${year}-12-31`)
        .order('closure_date'),
    ]);
    const { data: gaps } = await supabase.rpc('therapy_calendar_gaps', {
      p_from: `${year}-01-01`, p_to: `${year}-12-31`, p_country: country, p_region: null,
    });
    setBusy(false);
    if (ce || le) { setError((ce ?? le)!.message); return; }
    setError(null);
    setCountries((cs as Country[]) ?? []);
    setClosures((cl as Closure[]) ?? []);
    setCoverage(gaps ?? null);
  }, [year, country]);

  useEffect(() => { void load(); }, [load]);

  const visible = closures.filter(c => c.country_code === null || c.country_code === country);

  const add = async () => {
    if (!form.date || !form.name.trim()) { setError('A date and a name are required.'); return; }
    setBusy(true);
    const { error: e } = await supabase.rpc('upsert_therapy_closure_date', {
      p_id: null, p_date: form.date, p_kind: form.kind, p_name: form.name.trim(),
      p_country: form.scope === 'ALL' ? null : form.scope,
      p_region: form.region.trim() || null,
      p_observed_for: form.observedFor || null,
      p_source: form.source.trim() || null,
      p_source_reference: form.sourceRef.trim() || null,
      p_reason: form.reason.trim() || null,
    });
    setBusy(false);
    if (e) { setError(e.message); return; }
    setError(null); setNotice(`${form.name} added.`);
    setForm(f => ({ ...f, date: '', name: '', observedFor: '', reason: '' }));
    void load();
  };

  const remove = async (c: Closure) => {
    const { data: impact } = await supabase.rpc('therapy_closure_impact',
      { p_date: c.closure_date, p_country: c.country_code, p_region: c.region });
    const n = (impact as any[])?.length ?? 0;
    const ok = window.confirm(
      `Remove "${c.name}" on ${c.closure_date}?\n\n` +
      (n > 0
        ? `${n} active or scheduled entitlement(s) currently include this date.\n\n` +
          'Removing it does NOT shorten anyone automatically. Their expiry stays as granted ' +
          'until an Owner or Manager shortens it deliberately, with a reason.'
        : 'No active entitlement currently includes this date.'));
    if (!ok) return;
    const { error: e } = await supabase.rpc('delete_therapy_closure_date',
      { p_id: c.id, p_reason: 'Removed from the calendar' });
    if (e) { setError(e.message); return; }
    setNotice(`${c.name} removed. No expiry was shortened.`);
    void load();
  };

  const confirmCoverage = async () => {
    const source = window.prompt('Which source did you check these dates against?', 'mom.gov.sg');
    if (!source) return;
    const { error: e } = await supabase.rpc('set_therapy_calendar_coverage', {
      p_country: country, p_year: year, p_region: '*', p_verified: true,
      p_source: source, p_source_reference: null, p_notes: null,
    });
    if (e) { setError(e.message); return; }
    setNotice(`${country} ${year} marked as checked against ${source}.`);
    void load();
  };

  if (!canManage) {
    return <p className="therapy-remaining-hint">Holiday calendars are managed by Owners and Managers.</p>;
  }

  return (
    <div className="therapy-scope">
      <div style={{ display: 'flex', gap: 10, flexWrap: 'wrap', alignItems: 'flex-end', marginBottom: 10 }}>
        <div className="form-group" style={{ marginBottom: 0 }}>
          <label htmlFor="cal-country">Calendar</label>
          <select id="cal-country" value={country} onChange={e => setCountry(e.target.value)}>
            {countries.map(c => <option key={c.code} value={c.code}>{c.name} ({c.code})</option>)}
          </select>
        </div>
        <div className="form-group" style={{ marginBottom: 0 }}>
          <label htmlFor="cal-year">Year</label>
          <select id="cal-year" value={year} onChange={e => setYear(Number(e.target.value))}>
            {Array.from({ length: 7 }, (_, i) => new Date().getFullYear() - 2 + i)
              .map(y => <option key={y} value={y}>{y}</option>)}
          </select>
        </div>
        <button className="btn btn-secondary btn-sm" onClick={() => void load()} disabled={busy}>
          <RefreshCw size={13} aria-hidden="true" /> {busy ? 'Loading…' : 'Refresh'}
        </button>
      </div>

      {error && <div className="alert alert-danger" role="alert">{error}</div>}
      {notice && <div className="alert alert-success" role="status">{notice}</div>}

      {coverage && !coverage.verified && (
        <div className="alert alert-warning" role="status">
          <AlertTriangle size={15} aria-hidden="true" />
          <div>
            <strong>{country} {year} has not been checked against a source.</strong>{' '}
            Expiry dates spanning this year are shown as unverified until it has been.
            {(coverage.reasons ?? []).length > 0 && (
              <ul style={{ margin: '6px 0 0 18px' }}>
                {coverage.reasons.map((r: string, i: number) => <li key={i}>{r}</li>)}
              </ul>
            )}
            <button className="btn btn-secondary btn-sm" style={{ marginTop: 8 }} onClick={() => void confirmCoverage()}>
              I have checked these dates
            </button>
          </div>
        </div>
      )}
      {coverage?.verified && (
        <p className="therapy-remaining-hint">{country} {year} has been checked against a source.</p>
      )}

      <div className="table-wrap therapy-desktop-only">
        <table>
          <thead>
            <tr>
              <th scope="col">Date</th><th scope="col">Name</th><th scope="col">Kind</th>
              <th scope="col">Applies to</th><th scope="col">Source</th><th scope="col"></th>
            </tr>
          </thead>
          <tbody>
            {visible.length === 0 && (
              <tr><td colSpan={6} style={{ textAlign: 'center', color: 'var(--text-muted)', padding: 22 }}>
                No dates recorded for {country} in {year}. This is not the same as "no holidays" —
                entitlements spanning this year are flagged as unverified.
              </td></tr>
            )}
            {visible.map(c => (
              <tr key={c.id}>
                <td style={{ fontSize: 12.5 }}>{fmt(c.closure_date)}</td>
                <td>
                  <strong>{c.name}</strong>
                  {c.observed_for && <span className="therapy-remaining-hint"> · observed for {c.observed_for}</span>}
                </td>
                <td><span className="therapy-chip">
                  {c.kind === 'public_holiday' ? 'Public holiday' : 'Company closure'}
                </span></td>
                <td>{c.country_code === null
                  ? <span className="therapy-chip">All countries</span>
                  : <>{c.country_code}{c.region ? ` · ${c.region}` : ''}</>}</td>
                <td style={{ fontSize: 11.5, color: 'var(--text-muted)' }}>{c.source ?? '—'}</td>
                <td>
                  <button className="btn btn-secondary btn-sm" onClick={() => void remove(c)}
                          aria-label={`Remove ${c.name} on ${c.closure_date}`}>
                    <Trash2 size={13} aria-hidden="true" />
                  </button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      <div className="therapy-cards">
        {visible.map(c => (
          <div className="therapy-card" key={c.id}>
            <div className="therapy-card-head">
              <div>
                <div className="therapy-card-name">{c.name}</div>
                <div className="therapy-remaining-hint">{fmt(c.closure_date)}</div>
              </div>
              <button className="btn btn-secondary btn-sm" onClick={() => void remove(c)}
                      aria-label={`Remove ${c.name}`}><Trash2 size={13} aria-hidden="true" /></button>
            </div>
            <div className="therapy-card-stats">
              <span className="therapy-chip">{c.kind === 'public_holiday' ? 'Public holiday' : 'Company closure'}</span>
              <span className="therapy-chip">{c.country_code ?? 'All countries'}</span>
            </div>
          </div>
        ))}
      </div>

      <h4 style={{ fontSize: 13, margin: '18px 0 8px' }}>Add a date</h4>
      <div className="therapy-detail-grid">
        <div className="form-group">
          <label htmlFor="add-date">Date</label>
          <input id="add-date" type="date" value={form.date}
                 onChange={e => setForm(f => ({ ...f, date: e.target.value }))} />
        </div>
        <div className="form-group">
          <label htmlFor="add-name">Name</label>
          <input id="add-name" value={form.name} placeholder="e.g. National Day"
                 onChange={e => setForm(f => ({ ...f, name: e.target.value }))} />
        </div>
        <div className="form-group">
          <label htmlFor="add-kind">Kind</label>
          <select id="add-kind" value={form.kind} onChange={e => setForm(f => ({ ...f, kind: e.target.value }))}>
            <option value="public_holiday">Public holiday</option>
            <option value="company_closure">Company closure</option>
          </select>
        </div>
        <div className="form-group">
          <label htmlFor="add-scope">Applies to</label>
          <select id="add-scope" value={form.scope} onChange={e => setForm(f => ({ ...f, scope: e.target.value }))}>
            <option value="ALL">All countries</option>
            {countries.map(c => <option key={c.code} value={c.code}>{c.name} ({c.code}) only</option>)}
          </select>
        </div>
        <div className="form-group">
          <label htmlFor="add-observed">Observed for (optional)</label>
          <input id="add-observed" type="date" value={form.observedFor}
                 onChange={e => setForm(f => ({ ...f, observedFor: e.target.value }))} />
          <p className="therapy-remaining-hint">
            For a substitute day — e.g. a Monday standing in for a Sunday holiday. The Sunday
            itself earns no replacement day; this Monday does.
          </p>
        </div>
        <div className="form-group">
          <label htmlFor="add-source">Source</label>
          <input id="add-source" value={form.source} placeholder="e.g. mom.gov.sg gazette"
                 onChange={e => setForm(f => ({ ...f, source: e.target.value }))} />
        </div>
      </div>
      <button className="btn btn-primary btn-sm" onClick={() => void add()} disabled={busy}>
        <Plus size={14} aria-hidden="true" /> Add date
      </button>
    </div>
  );
};
