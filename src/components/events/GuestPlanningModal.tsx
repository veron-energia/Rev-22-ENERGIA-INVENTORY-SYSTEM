import React, { useId, useMemo, useState } from 'react';
import { supabase } from '../../lib/supabase';
import { Modal } from '../ui';
import {
  ACCESS_CHOICES, ACCESS_LABELS, AccessChoice, EventPlanning, EventRow, FOOD_CHOICES, FOOD_LABELS, FoodChoice, Guest,
  GuestPlanning, HEARD_FROM_CHOICES, HEARD_FROM_LABELS, HeardFromChoice, PLANNING_LIMITS, PlanningAnswers, PlanningDay,
  accessCell, allergyCell, dayLabel, emptyAnswers, fmtClock, fmtStamp, fmtWeekday, foodCell, heardFromCell, timeOptions, timingText,
} from './model';

/*
 * Guests → Answers (436 round 7, S1): a guest's planning answers in full, and
 * the staff form to change them on the guest's behalf (told by phone, say).
 * Whoever can edit guests can edit the answers (event_can_run); every change
 * is audited with the staff member and the note. The form sends the version it
 * was opened on: if the answers changed meanwhile (the guest on the website, or
 * other staff), the server refuses and says by whom, and the form stays open.
 *
 * The questions are the website's (the owner, 21 Oct 2026), in the third
 * person. Every one is optional ("Not answered"). A part of the day needs the
 * event's daily hours; without them only "Whole day" can be recorded. Talks:
 * the event's titles, then any title the guest chose that is no longer listed
 * (ticked; it can be unticked).
 */

type DayChoice = '' | 'whole' | 'part' | 'kept';
interface DayForm { choice: DayChoice; arrive: string; leave: string }
interface Form {
  food: FoodChoice | ''; food_other: string; allergy: '' | 'no' | 'yes'; allergy_details: string;
  days: Record<string, DayForm>; talks: string[]; access: AccessChoice[]; access_other: string;
  heard_from: HeardFromChoice | ''; heard_from_other: string; question: string; note: string;
}

const oneLine = (s: string): string | null => s.replace(/\s+/g, ' ').trim() || null;
const multiLine = (s: string): string | null => s.replace(/\r\n?/g, '\n').replace(/^[ \t\n]+|[ \t\n]+$/g, '') || null;

function formOf(a: PlanningAnswers, days: string[], start: string | null, end: string | null): Form {
  const opts = timeOptions(start, end);
  const dayForms: Record<string, DayForm> = {};
  for (const d of days) {
    const t = a.timing.find(x => x.date === d);
    dayForms[d] = !t ? { choice: '', arrive: opts.arrive[0] ?? '', leave: opts.leave[opts.leave.length - 1] ?? '' }
      : t.whole_day ? { choice: 'whole', arrive: opts.arrive[0] ?? '', leave: opts.leave[opts.leave.length - 1] ?? '' }
      // A part of the day kept under hours that are gone now stays as it was.
      : { choice: opts.arrive.length ? 'part' : 'kept', arrive: t.arrive ?? '', leave: t.leave ?? '' };
  }
  return {
    food: a.food ?? '', food_other: a.food_other ?? '', allergy: a.allergy ?? '', allergy_details: a.allergy_details ?? '',
    days: dayForms, talks: [...a.talks], access: [...a.access], access_other: a.access_other ?? '',
    heard_from: a.heard_from ?? '', heard_from_other: a.heard_from_other ?? '', question: a.question ?? '', note: '',
  };
}

/**
 * A kept talk whose title has since changed only in its capitals reads as the listed title, so it shows once, ticked
 * (the server matches titles ignoring case and keeps the listed spelling).
 */
export function withListedTalks(a: PlanningAnswers, titles: string[]): PlanningAnswers {
  const talks: string[] = [];
  for (const t of a.talks) {
    const listed = titles.find(x => x.toLowerCase() === t.toLowerCase()) ?? t;
    if (!talks.includes(listed)) talks.push(listed);
  }
  return { ...a, talks };
}

/** What is sent: every key, in the normal form (trimmed; a text only with its choice; "" is null). */
export function answersOf(f: Form, days: string[], titles: string[], start: string | null, end: string | null): PlanningAnswers {
  const timing: PlanningDay[] = [];
  for (const d of days) {
    const x = f.days[d];
    if (!x || !x.choice) continue;
    if (x.choice === 'whole' || (x.choice === 'part' && x.arrive === start && x.leave === end)) {
      timing.push({ date: d, whole_day: true, arrive: null, leave: null });
    } else if (x.arrive && x.leave) {
      timing.push({ date: d, whole_day: false, arrive: x.arrive, leave: x.leave });
    }
  }
  return {
    ...emptyAnswers(),
    food: f.food || null, food_other: f.food === 'other' ? oneLine(f.food_other) : null,
    allergy: f.allergy || null, allergy_details: f.allergy === 'yes' ? oneLine(f.allergy_details) : null,
    timing,
    // The list's order, then any chosen title no longer listed.
    talks: [...titles.filter(t => f.talks.includes(t)), ...f.talks.filter(t => !titles.includes(t))],
    access: ACCESS_CHOICES.filter(c => f.access.includes(c)), access_other: oneLine(f.access_other),
    heard_from: f.heard_from || null, heard_from_other: f.heard_from === 'other' ? oneLine(f.heard_from_other) : null,
    question: multiLine(f.question),
  };
}

export const GuestPlanningModal: React.FC<{
  event: EventRow;
  guest: Guest;
  row: GuestPlanning | null;
  /** The titles the website asks about now. */
  titles: string[];
  hours: EventPlanning['hours'];
  /** event.can_run: may change the answers. */
  canEdit: boolean;
  onClose: () => void;
  /** Saved: changed false when the answers were already these. */
  onSaved: (r: { changed: boolean }) => void;
}> = ({ event, guest, row, titles, hours, canEdit, onClose, onSaved }) => {
  const uid = useId();
  const answers = useMemo(() => withListedTalks(row?.answers ?? emptyAnswers(), titles), [row, titles]);
  const days = useMemo(() => (row && row.days.length ? row.days : guest.days.map(d => d.day)).slice().sort(), [row, guest]);
  const [editing, setEditing] = useState(false);
  const [form, setForm] = useState<Form>(() => formOf(answers, days, hours.start, hours.end));
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const opts = timeOptions(hours.start, hours.end);
  // The edit form's wording; the answers themselves read as the export and the website's sheet word them (section 5).
  const wholeText = hours.start && hours.end ? `Whole day (${fmtClock(hours.start)} – ${fmtClock(hours.end)})` : 'Whole day';
  const dayTitle = (d: string) => `${dayLabel(event, d)} · ${fmtWeekday(d)}`;
  const set = <K extends keyof Form>(k: K, v: Form[K]) => setForm(f => ({ ...f, [k]: v }));
  const setDay = (d: string, v: Partial<DayForm>) => setForm(f => ({ ...f, days: { ...f.days, [d]: { ...f.days[d], ...v } } }));
  const unlisted = answers.talks.filter(t => !titles.includes(t));
  const talkChoices = [...titles, ...unlisted];

  const save = async () => {
    setBusy(true); setErr(null);
    const { data, error } = await supabase.rpc('event_planning_save', {
      p_guest_id: guest.guest_id, p_answers: answersOf(form, days, titles, hours.start, hours.end),
      p_version: row?.version ?? 0, p_note: form.note.trim() || null,
    });
    setBusy(false);
    if (error) { setErr(error.message); return; }
    onSaved({ changed: (data as { changed?: boolean } | null)?.changed !== false });
  };

  const footer = editing ? (
    <>
      <button className="btn btn-secondary" onClick={() => { setEditing(false); setErr(null); setForm(formOf(answers, days, hours.start, hours.end)); }}
        disabled={busy}>Cancel</button>
      <button className="btn btn-primary" data-save-answers onClick={() => void save()} disabled={busy}>{busy ? 'Saving…' : 'Save answers'}</button>
    </>
  ) : (
    <>
      <button className="btn btn-secondary" onClick={onClose}>Close</button>
      {canEdit && <button className="btn btn-primary" data-edit-answers onClick={() => setEditing(true)}>Edit answers</button>}
    </>
  );

  const na = <span className="events-muted">Not answered</span>;
  const updated = !row?.updated_at ? 'No answers yet.'
    : row.updated_by === 'staff' ? `Last changed by ${row.staff_name ?? 'staff'} on ${fmtStamp(row.updated_at)}.`
    : `Answered on the website on ${fmtStamp(row.updated_at)}.`;

  return (
    <Modal title={`${guest.name}: answers`} maxWidth={560} onClose={onClose} confirmClose={editing} footer={footer}>
      <div data-plan-modal className="events-plan-modal">
        {err && <div className="alert alert-danger" role="alert"><span>⚠</span><div>{err}</div></div>}
        {!editing ? (
          <dl className="events-plan-detail">
            <dt>Food</dt>
            <dd data-answer="food">{foodCell(answers) || na}</dd>
            <dt>Allergies</dt>
            <dd data-answer="allergy">{answers.allergy === 'yes'
              ? <span className="events-plan-allergy">{allergyCell(answers)}</span>
              : (allergyCell(answers) || na)}</dd>
            {days.map(d => {
              const t = answers.timing.find(x => x.date === d);
              return (
                <React.Fragment key={d}>
                  <dt>{dayTitle(d)}</dt>
                  <dd data-answer-day={d}>{!t ? na : timingText(t, hours.start, hours.end)}</dd>
                </React.Fragment>
              );
            })}
            <dt>Talks</dt>
            <dd data-answer="talks">{answers.talks.length === 0 ? <span className="events-muted">None chosen</span>
              : answers.talks.map(t => <div key={t}>{t}{titles.includes(t) ? '' : <span className="events-muted"> (no longer listed)</span>}</div>)}</dd>
            <dt>To prepare</dt>
            <dd data-answer="access">{accessCell(answers) || na}</dd>
            <dt>Heard about it from</dt>
            <dd data-answer="heard">{heardFromCell(answers) || na}</dd>
            <dt>Question for the speakers</dt>
            <dd data-answer="question" style={{ whiteSpace: 'pre-wrap' }}>{answers.question ?? <span className="events-muted">None</span>}</dd>
          </dl>
        ) : (
          <div className="form-grid events-plan-form">
            <fieldset className="events-plan-q">
              <legend>Any dietary preference?</legend>
              <div className="events-plan-choices">
                {(['', ...FOOD_CHOICES] as (FoodChoice | '')[]).map(c => (
                  <label key={c || 'na'} className="events-inline">
                    <input type="radio" name={`${uid}-food`} checked={form.food === c} onChange={() => set('food', c)} />
                    {c ? FOOD_LABELS[c] : 'Not answered'}
                  </label>
                ))}
              </div>
              {form.food === 'other' && (
                <input aria-label="Which?" placeholder="e.g. No pork" maxLength={PLANNING_LIMITS.food_other}
                  value={form.food_other} onChange={e => set('food_other', e.target.value)} />
              )}
            </fieldset>

            <fieldset className="events-plan-q">
              <legend>Any food allergies?</legend>
              <div className="events-plan-choices">
                {([['', 'Not answered'], ['no', 'No'], ['yes', 'Yes']] as ['' | 'no' | 'yes', string][]).map(([v, l]) => (
                  <label key={l} className="events-inline">
                    <input type="radio" name={`${uid}-allergy`} checked={form.allergy === v} onChange={() => set('allergy', v)} />{l}
                  </label>
                ))}
              </div>
              {form.allergy === 'yes' && (
                <input aria-label="Which allergies?" placeholder="e.g. Peanuts, shellfish" maxLength={PLANNING_LIMITS.allergy_details}
                  value={form.allergy_details} onChange={e => set('allergy_details', e.target.value)} />
              )}
            </fieldset>

            <div className="events-plan-q">
              <div className="events-section-title">Timing</div>
              {!opts.arrive.length && (
                <div className="events-sub" data-no-hours>The event has no daily hours (Edit event), so part-day times cannot be recorded.</div>
              )}
              {days.length === 0 && <div className="events-sub">No days.</div>}
              {days.map(d => {
                const x = form.days[d];
                const arrive = opts.arrive.includes(x.arrive) || !x.arrive ? opts.arrive : [...opts.arrive, x.arrive].sort();
                const leaveAll = opts.leave.includes(x.leave) || !x.leave ? opts.leave : [...opts.leave, x.leave].sort();
                const leave = leaveAll.filter(t => t > x.arrive);
                const kept = answers.timing.find(t => t.date === d && !t.whole_day);
                return (
                  <fieldset key={d} className="events-plan-day" data-plan-day={d}>
                    <legend>{dayTitle(d)}</legend>
                    <div className="events-plan-choices">
                      <label className="events-inline"><input type="radio" name={`${uid}-day-${d}`} checked={x.choice === ''}
                        onChange={() => setDay(d, { choice: '' })} />Not answered</label>
                      <label className="events-inline"><input type="radio" name={`${uid}-day-${d}`} checked={x.choice === 'whole'}
                        onChange={() => setDay(d, { choice: 'whole' })} />{wholeText}</label>
                      {opts.arrive.length > 0 && (
                        <label className="events-inline"><input type="radio" name={`${uid}-day-${d}`} checked={x.choice === 'part'}
                          onChange={() => setDay(d, { choice: 'part', arrive: x.arrive || opts.arrive[0], leave: x.leave || opts.leave[opts.leave.length - 1] })} />
                          Part of the day</label>
                      )}
                      {!opts.arrive.length && kept && (
                        <label className="events-inline"><input type="radio" name={`${uid}-day-${d}`} checked={x.choice === 'kept'}
                          onChange={() => setDay(d, { choice: 'kept', arrive: kept.arrive ?? '', leave: kept.leave ?? '' })} />
                          As answered: {fmtClock(kept.arrive)} – {fmtClock(kept.leave)}</label>
                      )}
                    </div>
                    {x.choice === 'part' && (
                      <div className="events-plan-times">
                        <label>Arriving around
                          <select aria-label={`Arriving around, ${dayTitle(d)}`} value={x.arrive} onChange={e => {
                            const a = e.target.value;
                            setDay(d, { arrive: a, leave: x.leave > a ? x.leave : (leaveAll.find(t => t > a) ?? '') });
                          }}>
                            {arrive.map(t => <option key={t} value={t}>{fmtClock(t)}</option>)}
                          </select>
                        </label>
                        <label>Leaving around
                          <select aria-label={`Leaving around, ${dayTitle(d)}`} value={x.leave} onChange={e => setDay(d, { leave: e.target.value })}>
                            {leave.map(t => <option key={t} value={t}>{fmtClock(t)}</option>)}
                          </select>
                        </label>
                      </div>
                    )}
                  </fieldset>
                );
              })}
            </div>

            {talkChoices.length > 0 && (
              <fieldset className="events-plan-q" data-plan-talks>
                <legend>Which talks interest them most?</legend>
                {talkChoices.map(t => (
                  <label key={t} className="events-inline">
                    <input type="checkbox" checked={form.talks.includes(t)}
                      onChange={() => set('talks', form.talks.includes(t) ? form.talks.filter(x => x !== t) : [...form.talks, t])} />
                    {t}{titles.includes(t) ? '' : <span className="events-muted"> (no longer listed)</span>}
                  </label>
                ))}
              </fieldset>
            )}

            <fieldset className="events-plan-q">
              <legend>Anything we should prepare?</legend>
              {ACCESS_CHOICES.map(c => (
                <label key={c} className="events-inline">
                  <input type="checkbox" checked={form.access.includes(c)}
                    onChange={() => set('access', form.access.includes(c) ? form.access.filter(x => x !== c) : [...form.access, c])} />
                  {ACCESS_LABELS[c]}
                </label>
              ))}
              <input aria-label="Anything else?" placeholder="Anything else?" maxLength={PLANNING_LIMITS.access_other}
                value={form.access_other} onChange={e => set('access_other', e.target.value)} />
            </fieldset>

            <div className="form-group events-plan-q">
              <label htmlFor={`${uid}-heard`}>How did they hear about the seminar?</label>
              <select id={`${uid}-heard`} aria-label="How did they hear about the seminar?" value={form.heard_from}
                onChange={e => set('heard_from', e.target.value as HeardFromChoice | '')}>
                <option value="">Not answered</option>
                {HEARD_FROM_CHOICES.map(c => <option key={c} value={c}>{HEARD_FROM_LABELS[c]}</option>)}
              </select>
              {form.heard_from === 'other' && (
                <input aria-label="Where?" placeholder="Where?" maxLength={PLANNING_LIMITS.heard_from_other}
                  value={form.heard_from_other} onChange={e => set('heard_from_other', e.target.value)} />
              )}
            </div>

            <div className="form-group events-plan-q">
              <label htmlFor={`${uid}-question`}>A question for our speakers?</label>
              <textarea id={`${uid}-question`} rows={3} maxLength={PLANNING_LIMITS.question} value={form.question}
                onChange={e => set('question', e.target.value)} />
              <div className="events-sub">{form.question.length} / {PLANNING_LIMITS.question}</div>
            </div>

            <div className="form-group events-plan-q" style={{ marginBottom: 0 }}>
              <label htmlFor={`${uid}-note`}>Note for the log (optional)</label>
              <input id={`${uid}-note`} aria-label="Note for the log" placeholder="e.g. Told by phone on 21 Nov"
                maxLength={PLANNING_LIMITS.note} value={form.note} onChange={e => set('note', e.target.value)} />
            </div>
          </div>
        )}
        <div className="events-sub" data-plan-updated style={{ marginTop: 10 }}>{updated}</div>
      </div>
    </Modal>
  );
};

export default GuestPlanningModal;
