import React, { useCallback, useEffect, useRef, useState } from 'react';
import { AlertTriangle, Crown, RefreshCw } from 'lucide-react';
import { supabase } from '../../lib/supabase';
import {
  ACCESS_LABELS, EventRow, FOOD_LABELS, FoodCounts, HEARD_FROM_CHOICES, HEARD_FROM_LABELS, PlanPerson, PlanningSummary,
  TWO_VIP_PAYMENTS, dayLabel, fmtClock, fmtWeekday, normalizePlanningSummary, vipHeldText,
} from './model';

/*
 * Event → Planning (436 round 7, S2): what the guests answered, for the kitchen
 * and the organiser. One card per day (food counts, allergies, who arrives late
 * or leaves early, what to prepare), the VIP guests' food and allergies
 * (VIP payments still waiting are counted apart), the talks they are
 * interested in, how they heard about the seminar, and their questions for the
 * speakers. Counted by the server (event_planning_summary) over the guests
 * registered now; whoever sees the guest list sees it.
 */

const FOOD_ORDER: (keyof FoodCounts)[] = ['vegetarian', 'vegan', 'halal', 'no_beef', 'other', 'no_preference', 'not_said'];
const foodName = (k: keyof FoodCounts) => (k === 'not_said' ? 'Not answered' : FOOD_LABELS[k]);

const FoodChips: React.FC<{ food: FoodCounts }> = ({ food }) => (
  <div className="events-chips" data-plan-food>
    {FOOD_ORDER.map(k => (
      <span key={k} className={`events-chip${k === 'not_said' || k === 'no_preference' ? '' : ' events-chip-price'}`} data-food={k}>
        {foodName(k)} {food[k]}
      </span>
    ))}
  </div>
);

const Who: React.FC<{ p: PlanPerson }> = ({ p }) => (
  <>{p.name}{p.vip && <Crown size={11} aria-label="VIP" className="events-plan-vip" />}</>
);

const Allergies: React.FC<{ list: (PlanPerson & { text: string | null })[] }> = ({ list }) => (
  <div className="events-plan-block" data-plan-allergies>
    <div className="events-plan-allergy">Allergies ({list.length})</div>
    {list.length === 0 ? <div className="events-sub">No allergies given.</div> : (
      <ul className="events-plan-list">
        {list.map(a => <li key={a.guest_id}><Who p={a} /> — <span className="events-plan-allergy">{a.text ?? '(not said which)'}</span></li>)}
      </ul>
    )}
  </div>
);

/** "2:00 pm (3) · 3:00 pm (1)" */
function byTime(list: { time: string }[]): string {
  const counts: Record<string, number> = {};
  for (const x of list) counts[x.time] = (counts[x.time] ?? 0) + 1;
  return Object.keys(counts).sort().map(t => `${fmtClock(t)} (${counts[t]})`).join(' · ');
}

export const PlanningTab: React.FC<{ event: EventRow; hasWebsite: boolean }> = ({ event, hasWebsite }) => {
  const [summary, setSummary] = useState<PlanningSummary | null>(null);
  const [loading, setLoading] = useState(true);
  const [err, setErr] = useState<string | null>(null);
  const [missing, setMissing] = useState(false);
  const seq = useRef(0);

  const load = useCallback(async () => {
    const mine = ++seq.current;
    setLoading(true);
    const { data, error } = await supabase.rpc('event_planning_summary', { p_event_id: event.id });
    if (mine !== seq.current) return;
    setLoading(false);
    if (!error) { setSummary(normalizePlanningSummary(data)); setErr(null); setMissing(false); return; }
    if (error.code === 'PGRST202' || error.code === '42883') { setMissing(true); setErr(null); return; }
    // A failed read keeps what was shown, and says so.
    setErr(`Could not load the planning summary; showing what was loaded before. ${error.message}`);
  }, [event.id]);
  useEffect(() => { void load(); }, [load]);

  if (missing) return <div className="card empty-state"><p>Planning needs migration 436 (round 7).</p></div>;
  if (!summary) {
    return err
      ? <div className="alert alert-danger" role="alert"><span>⚠</span><div>{err}</div></div>
      : <div className="card empty-state"><RefreshCw size={24} className="spin" style={{ opacity: 0.4 }} /></div>;
  }
  const s = summary;
  const heard = [...HEARD_FROM_CHOICES].filter(c => s.heard_from[c] > 0).sort((a, b) => s.heard_from[b] - s.heard_from[a]);
  const maxTalk = Math.max(1, s.answered, ...s.talks.map(t => t.count));

  return (
    <div className="events-planning" data-planning-tab>
      {err && <div className="alert alert-warning" role="alert"><span>⚠</span><div>{err}</div></div>}
      <div className="card events-plan-top">
        <div>
          <strong data-plan-answered>Answers from {s.answered} of {s.registered} registered guests</strong>
          {s.answered === 0 && (
            <div className="events-sub" data-plan-none>
              No answers yet. Guests answer on the website's thank-you page or their personal link; staff can add answers from
              Guests → Answers.
            </div>
          )}
          {!hasWebsite && s.answered > 0 && <div className="events-sub">Answers recorded by staff (this event has no website).</div>}
        </div>
        <button className="btn btn-secondary btn-sm" onClick={() => void load()}>
          <RefreshCw size={13} className={loading ? 'spin' : ''} /> Refresh
        </button>
      </div>

      <div className="events-plan-grid">
        {s.days.map(d => (
          <div key={d.day} className="card events-plan-card" data-planning-day={d.day}>
            <div className="events-plan-card-head">
              <strong>{d.label || dayLabel(event, d.day)} · {fmtWeekday(d.day)}</strong>
              <span className="events-sub">{d.registered} coming · {d.answered} answered</span>
            </div>
            <div className="events-plan-block">
              <div className="events-section-title">Food</div>
              <FoodChips food={d.food} />
              {d.food_other.length > 0 && (
                <ul className="events-plan-list" data-plan-food-other>
                  {d.food_other.map(f => <li key={f.guest_id}>Other food: <Who p={f} /> — {f.text || '(not said which)'}</li>)}
                </ul>
              )}
            </div>
            <Allergies list={d.allergies} />
            <div className="events-plan-block" data-plan-late>
              <div className="events-section-title">Arriving late ({d.late.length})</div>
              {d.late.length > 0 && <div className="events-sub">{byTime(d.late)}</div>}
              <ul className="events-plan-list">{d.late.map(x => <li key={x.guest_id}>{fmtClock(x.time)} · <Who p={x} /></li>)}</ul>
            </div>
            <div className="events-plan-block" data-plan-early>
              <div className="events-section-title">Leaving early ({d.early.length})</div>
              {d.early.length > 0 && <div className="events-sub">{byTime(d.early)}</div>}
              <ul className="events-plan-list">{d.early.map(x => <li key={x.guest_id}>{fmtClock(x.time)} · <Who p={x} /></li>)}</ul>
            </div>
            <div className="events-plan-block" data-plan-access>
              <div className="events-section-title">To prepare ({d.access.length})</div>
              <ul className="events-plan-list">
                {d.access.map(x => (
                  <li key={x.guest_id}><Who p={x} /> — {[...x.needs.map(n => ACCESS_LABELS[n]), ...(x.other ? [`Other: ${x.other}`] : [])].join('; ')}</li>
                ))}
              </ul>
            </div>
          </div>
        ))}

        {s.vip && (
          <div className="card events-plan-card events-plan-vip-card" data-planning-vip>
            <div className="events-plan-card-head">
              <strong><Crown size={13} /> VIP guests</strong>
              <span className="events-sub">{s.vip.count} VIP{s.vip.count === 1 ? '' : 's'} · {s.vip.answered} answered</span>
              {s.vip.waiting > 0 && (
                <span className="events-sub" data-plan-vip-waiting>
                  {s.vip.waiting === 1
                    ? '1 more VIP payment waits to be confirmed (not counted here).'
                    : `${s.vip.waiting} more VIP payments wait to be confirmed (not counted here).`}
                </span>
              )}
            </div>
            {s.vip.doubles.length > 0 && (
              <div className="alert alert-warning events-plan-vip-doubles" role="note" data-plan-vip-doubles>
                <AlertTriangle size={15} />
                <div>
                  <strong>{TWO_VIP_PAYMENTS}</strong>
                  <ul>
                    {s.vip.doubles.map(d => (
                      <li key={d.customer_id} data-plan-vip-double={d.customer_id}>{d.full_name}: {vipHeldText(d.vips)} (counted once)</li>
                    ))}
                  </ul>
                </div>
              </div>
            )}
            <div className="events-plan-block">
              <div className="events-section-title">Food</div>
              <FoodChips food={s.vip.food} />
              {s.vip.food_other.length > 0 && (
                <ul className="events-plan-list">{s.vip.food_other.map(f => <li key={f.guest_id}>Other food: {f.name} — {f.text || '(not said which)'}</li>)}</ul>
              )}
            </div>
            <Allergies list={s.vip.allergies} />
          </div>
        )}

        <div className="card events-plan-card" data-planning-talks>
          <div className="events-plan-card-head"><strong>Talks they are interested in</strong></div>
          {s.talks.length === 0 ? <div className="events-sub">No talks are asked about.</div> : (
            <ul className="events-plan-list events-plan-talks">
              {s.talks.map(t => (
                <li key={t.title} data-talk={t.title}>
                  <div className="events-plan-talk-line">
                    <span>{t.title}{!t.listed && <span className="events-muted"> (no longer listed)</span>}</span>
                    <strong className="events-num">{t.count}</strong>
                  </div>
                  <div className="events-plan-bar" aria-hidden="true"><span style={{ width: `${Math.round((t.count / maxTalk) * 100)}%` }} /></div>
                </li>
              ))}
            </ul>
          )}
        </div>

        <div className="card events-plan-card" data-planning-heard>
          <div className="events-plan-card-head"><strong>How they heard about the seminar</strong></div>
          <div className="events-chips">
            {heard.map(c => <span key={c} className="events-chip events-chip-price" data-heard={c}>{HEARD_FROM_LABELS[c]} {s.heard_from[c]}</span>)}
            <span className="events-chip" data-heard="not_said">Not answered {s.heard_from.not_said}</span>
          </div>
          {s.heard_from_other.length > 0 && (
            <ul className="events-plan-list">{s.heard_from_other.map(h => <li key={h.guest_id}>Other: {h.name} — {h.text}</li>)}</ul>
          )}
        </div>
      </div>

      <details className="card events-plan-questions" data-planning-questions>
        <summary>Questions for the speakers ({s.questions.length})</summary>
        {s.questions.length === 0 ? <div className="events-sub">None yet.</div> : (
          <ul className="events-plan-list">
            {s.questions.map(q => <li key={q.guest_id} style={{ whiteSpace: 'pre-wrap' }}><strong>{q.name}</strong>: {q.text}</li>)}
          </ul>
        )}
      </details>
    </div>
  );
};

export default PlanningTab;
