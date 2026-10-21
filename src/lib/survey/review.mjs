// Save Review in the survey window (CUSTOMERS-K1).
//
// After a save the window used to empty the Goals, Condition and
// Recommendation boxes while Save Review stayed on, so a second press saved
// the empty boxes over the review (22 times from 6 Aug to 15 Oct 2026). The
// boxes now show what is saved, Save Review is off until something differs,
// and emptied boxes never replace a saved review (the server refuses that
// too, unless asked to clear it).

const tidy = v => {
  const s = v == null ? '' : String(v).trim();
  return s === '' ? null : s;
};

/** The review as saved on the survey. */
export function savedReview(survey) {
  const s = survey ?? {};
  return {
    acidity: tidy(s.acidity_result), goals: tidy(s.health_goals),
    cond: tidy(s.remarks_condition), rec: tidy(s.remarks_recommendation),
  };
}

/**
 * What Save Review may do with the boxes as they are:
 *   changed  - something differs from what is saved;
 *   blanks   - the three text boxes are empty while the saved review has text
 *              (saving would not clear it: the server keeps it);
 *   canSave  - changed, and not blanks.
 */
export function reviewState(saved, draft) {
  const a = saved ?? {};
  const b = { acidity: tidy(draft?.acidity), goals: tidy(draft?.goals), cond: tidy(draft?.cond), rec: tidy(draft?.rec) };
  const changed = a.acidity !== b.acidity || a.goals !== b.goals || a.cond !== b.cond || a.rec !== b.rec;
  const blanks = b.goals === null && b.cond === null && b.rec === null
    && (a.goals !== null || a.cond !== null || a.rec !== null);
  return { changed, blanks, canSave: changed && !blanks };
}
