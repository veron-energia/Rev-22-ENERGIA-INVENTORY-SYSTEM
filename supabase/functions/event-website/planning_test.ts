// Planning answers (436, round 7, the owner 21 Oct 2026): the message as the website sends it, its whitelist and
// limits, the labels, and the time options both sides offer (436 checks the same rule). contract_test.ts proves the
// suggested talk titles are the ones in 436.

import { assertEquals } from 'jsr:@std/assert@1';
import { validateRequest } from './validate.ts';
import { messages, TOKEN_1 } from './fixtures.ts';
import {
  ACCESS_CHOICES, ACCESS_LABELS, FOOD_CHOICES, FOOD_LABELS, HEARD_FROM_CHOICES, HEARD_FROM_LABELS, isWriteType,
  planningTimeOptions, READ_TYPES, SUGGESTED_TALK_TITLES, WRITE_TYPES,
} from './contract.ts';
import { aboutOf } from './validate.ts';

const clone = <T>(v: T): T => structuredClone(v);
// deno-lint-ignore no-explicit-any
type Any = any;
const refused = (body: unknown) => validateRequest(body) as { ok: false; field: string };
const plan = (): Any => clone(messages().planning_answers);
const ans = (b: Any, i = 0) => b.planning.people[i].answers;

Deno.test('planning_answers is a write, the tenth message', () => {
  assertEquals([...WRITE_TYPES, ...READ_TYPES].length, 10);
  assertEquals(isWriteType('planning_answers'), true);
  assertEquals(aboutOf(messages().planning_answers), {});
});

Deno.test('planning_answers as the website sends it passes and comes back the same', () => {
  assertEquals(validateRequest(plan()), { ok: true, value: messages().planning_answers });
});

Deno.test('planning_answers: unknown keys at every level are refused with their path', () => {
  const cases: [(b: Any) => void, string][] = [
    [(b) => { b.planning.x = 1; }, 'planning.x'],
    [(b) => { b.planning.people[0].x = 1; }, 'planning.people.0.x'],
    [(b) => { ans(b).x = 1; }, 'planning.people.0.answers.x'],
    [(b) => { ans(b).timing[0].x = 1; }, 'planning.people.0.answers.timing.0.x'],
  ];
  for (const [change, field] of cases) { const b = plan(); change(b); assertEquals(refused(b), { ok: false, field }); }
});

Deno.test('planning_answers: every field is required; null only where the contract allows it', () => {
  const cases: [(b: Any) => void, string][] = [
    [(b) => { delete ans(b).food; }, 'planning.people.0.answers.food'],
    [(b) => { ans(b).timing = null; }, 'planning.people.0.answers.timing'],
    [(b) => { ans(b).talks = null; }, 'planning.people.0.answers.talks'],
    [(b) => { ans(b).access = null; }, 'planning.people.0.answers.access'],
    [(b) => { b.planning.people[0].version = null; }, 'planning.people.0.version'],
    [(b) => { delete b.planning.people[0].version; }, 'planning.people.0.version'],
    [(b) => { b.planning.submitted_at = '2026-11-01T10:00:00'; }, 'planning.submitted_at'],
  ];
  for (const [change, field] of cases) { const b = plan(); change(b); assertEquals(refused(b), { ok: false, field }); }
  const empty = plan();
  Object.assign(ans(empty), { food: null, allergy: null, allergy_details: null, timing: [], talks: [], access: [],
    heard_from: null, heard_from_other: null });
  assertEquals(validateRequest(empty).ok, true);
});

Deno.test("planning_answers: the choices are the contract's", () => {
  const cases: [(b: Any) => void, string][] = [
    [(b) => { ans(b).food = 'pescatarian'; }, 'planning.people.0.answers.food'],
    [(b) => { ans(b).allergy = 'maybe'; }, 'planning.people.0.answers.allergy'],
    [(b) => { ans(b).access = ['lift']; }, 'planning.people.0.answers.access.0'],
    [(b) => { ans(b).heard_from = 'radio'; }, 'planning.people.0.answers.heard_from'],
  ];
  for (const [change, field] of cases) { const b = plan(); change(b); assertEquals(refused(b), { ok: false, field }); }
});

Deno.test('planning_answers: a text that goes with a choice only with it', () => {
  const cases: [(b: Any) => void, string][] = [
    [(b) => { ans(b).food = 'vegan'; ans(b).food_other = 'No pork'; }, 'planning.people.0.answers.food_other'],
    [(b) => { ans(b).allergy = 'no'; ans(b).allergy_details = 'Peanuts'; }, 'planning.people.0.answers.allergy_details'],
    [(b) => { ans(b).heard_from = 'tiktok'; ans(b).heard_from_other = 'Radio'; }, 'planning.people.0.answers.heard_from_other'],
  ];
  for (const [change, field] of cases) { const b = plan(); change(b); assertEquals(refused(b), { ok: false, field }); }
  const ok = plan();
  ans(ok).food = 'other'; ans(ok).food_other = '  No pork  ';
  assertEquals((validateRequest(ok) as Any).value.planning.people[0].answers.food_other, 'No pork');
  const yes = plan(); ans(yes).allergy = 'yes';
  assertEquals(validateRequest(yes).ok, true); // details may stay null
});

Deno.test('planning_answers: limits', () => {
  const p = 'planning.people.0.answers';
  const cases: [(b: Any) => void, string][] = [
    [(b) => { ans(b).food = 'other'; ans(b).food_other = 'x'.repeat(61); }, `${p}.food_other`],
    [(b) => { ans(b).allergy = 'yes'; ans(b).allergy_details = 'x'.repeat(121); }, `${p}.allergy_details`],
    [(b) => { ans(b).access_other = 'x'.repeat(121); }, `${p}.access_other`],
    [(b) => { ans(b).heard_from = 'other'; ans(b).heard_from_other = 'x'.repeat(61); }, `${p}.heard_from_other`],
    [(b) => { ans(b).question = 'x'.repeat(301); }, `${p}.question`],
    [(b) => { ans(b).talks = ['x'.repeat(121)]; }, `${p}.talks.0`],
    [(b) => { ans(b).talks = Array.from({ length: 21 }, (_, i) => `Talk ${i}`); }, `${p}.talks`],
    [(b) => { ans(b).talks = ['Caring for your eyes', 'Caring for your eyes']; }, `${p}.talks`],
    [(b) => { ans(b).access = ['wheelchair', 'walking_help', 'front_seat', 'wheelchair']; }, `${p}.access`],
    [(b) => { ans(b).access = ['wheelchair', 'wheelchair']; }, `${p}.access`],
    [(b) => { ans(b).timing = Array.from({ length: 32 }, () => ({ date: '2026-11-23', whole_day: true, arrive: null, leave: null })); }, `${p}.timing`],
    [(b) => { ans(b).timing = [ans(b).timing[0], ans(b).timing[0]]; }, `${p}.timing`],
    [(b) => { ans(b).question = ''; }, `${p}.question`],
    [(b) => { ans(b).question = '   '; }, `${p}.question`],
  ];
  for (const [change, field] of cases) { const b = plan(); change(b); assertEquals(refused(b), { ok: false, field }); }
  const max = plan();
  Object.assign(ans(max), { food: 'other', food_other: 'x'.repeat(60), question: 'x'.repeat(300), access_other: 'x'.repeat(120) });
  assertEquals(validateRequest(max).ok, true);
});

Deno.test('planning_answers: times', () => {
  const t = 'planning.people.0.answers.timing.1';
  const cases: [Any, string][] = [
    [{ date: '2026-11-24', whole_day: false, arrive: '9:00', leave: '19:00' }, `${t}.arrive`],
    [{ date: '2026-11-24', whole_day: false, arrive: '09:00', leave: '24:00' }, `${t}.leave`],
    [{ date: '2026-11-24', whole_day: false, arrive: '09:60', leave: '19:00' }, `${t}.arrive`],
    [{ date: '2026-11-24', whole_day: false, arrive: '14:00', leave: '14:00' }, `${t}.leave`],
    [{ date: '2026-11-24', whole_day: false, arrive: '15:00', leave: '14:00' }, `${t}.leave`],
    [{ date: '2026-11-24', whole_day: true, arrive: '09:00', leave: null }, `${t}.arrive`],
    [{ date: '2026-11-24', whole_day: false, arrive: null, leave: '19:00' }, `${t}.arrive`],
    [{ date: '2026-11-24', whole_day: 'yes', arrive: null, leave: null }, `${t}.whole_day`],
    [{ date: '2026-02-30', whole_day: true, arrive: null, leave: null }, `${t}.date`],
  ];
  for (const [day, field] of cases) { const b = plan(); ans(b).timing[1] = day; assertEquals(refused(b), { ok: false, field }); }
});

Deno.test('planning_answers: people 1..10 with distinct tokens; version a whole number 0..1000000', () => {
  const none = plan(); none.planning.people = [];
  assertEquals(refused(none), { ok: false, field: 'planning.people' });
  const eleven = plan();
  eleven.planning.people = Array.from({ length: 11 }, (_, i) => ({ ...clone(eleven.planning.people[0]),
    upgrade_token: 'vip_' + 'abcdefghijklmnopqrstuvwxyz'.slice(0, 25) + 'abcdefghijk'[i] }));
  assertEquals(refused(eleven), { ok: false, field: 'planning.people' });
  const twice = plan(); twice.planning.people[1].upgrade_token = TOKEN_1;
  assertEquals(refused(twice), { ok: false, field: 'planning.people' });
  for (const v of [-1, 1.5, '1', 1_000_001]) {
    const b = plan(); b.planning.people[0].version = v;
    assertEquals(refused(b), { ok: false, field: 'planning.people.0.version' });
  }
  const bad = plan(); bad.planning.people[0].upgrade_token = 'vip_x';
  assertEquals(refused(bad), { ok: false, field: 'planning.people.0.upgrade_token' });
});

Deno.test('planning_answers: a line break is allowed, a control character or a lone surrogate is not', () => {
  const ok = plan(); ans(ok).question = 'One\r\nTwo';
  assertEquals(validateRequest(ok).ok, true);
  for (const q of ['Bell\u0007', 'Half \ud800 pair', 'Nul\u0000']) {
    const b = plan(); ans(b).question = q;
    assertEquals(refused(b), { ok: false, field: 'planning.people.0.answers.question' });
  }
});

Deno.test('the planning choices and labels hang together', () => {
  for (const [list, labels] of [[FOOD_CHOICES, FOOD_LABELS], [ACCESS_CHOICES, ACCESS_LABELS], [HEARD_FROM_CHOICES, HEARD_FROM_LABELS]] as [readonly string[], Record<string, string>][]) {
    assertEquals(new Set(list).size, list.length);
    assertEquals(Object.keys(labels).sort(), [...list].sort());
  }
  assertEquals(SUGGESTED_TALK_TITLES.length, 7);
});

Deno.test('planningTimeOptions: the half hours within the hours, as 436 checks them', () => {
  const nine = planningTimeOptions('09:00', '19:00');
  assertEquals([nine.arrive.length, nine.arrive[0], nine.arrive.at(-1)], [20, '09:00', '18:30']);
  assertEquals([nine.leave.length, nine.leave[0], nine.leave.at(-1)], [20, '09:30', '19:00']);
  assertEquals(planningTimeOptions('09:00', '18:45'), {
    arrive: ['09:00', '09:30', '10:00', '10:30', '11:00', '11:30', '12:00', '12:30', '13:00', '13:30', '14:00', '14:30', '15:00',
             '15:30', '16:00', '16:30', '17:00', '17:30', '18:00'],
    leave: ['09:30', '10:00', '10:30', '11:00', '11:30', '12:00', '12:30', '13:00', '13:30', '14:00', '14:30', '15:00', '15:30',
            '16:00', '16:30', '17:00', '17:30', '18:00', '18:30', '18:45'],
  });
  assertEquals(planningTimeOptions('10:15', '11:00'), { arrive: ['10:15'], leave: ['10:45', '11:00'] });
  assertEquals(planningTimeOptions('09:00', '09:20'), { arrive: [], leave: [] });
  assertEquals(planningTimeOptions(null, '19:00'), { arrive: [], leave: [] });
  assertEquals(planningTimeOptions('9:00', '19:00'), { arrive: [], leave: [] });
});

