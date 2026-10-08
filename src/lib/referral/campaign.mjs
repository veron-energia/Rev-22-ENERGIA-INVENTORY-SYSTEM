// Visits, downlines and referral promotions on screen (398, 404). The
// database decides who visited, who counts and which tier is reached
// (customer_centre_visits, referral_campaign_friends,
// referral_campaign_standing); these helpers only shape what the pages send
// and show, so the wording and the request stay the same everywhere.

/** search_customers' Visited and first-visit filters, as the Customers page
 *  sends them. "Not visited" has no first visit, so its dates are dropped.
 *  Only the filters in use are sent: with none, the call is the four
 *  arguments it always was. */
export function visitFilterArgs(visited, from, to) {
  const v = visited === 'visited' || visited === 'not_visited' ? visited : null;
  const date = d => (/^\d{4}-\d{2}-\d{2}$/.test(String(d ?? '')) ? String(d) : null);
  const out = {};
  if (v) out.p_visited = v;
  if (v !== 'not_visited') {
    if (date(from)) out.p_visit_from = date(from);
    if (date(to)) out.p_visit_to = date(to);
  }
  return out;
}

/** True when any visit filter is on. */
export function visitFilterActive(visited, from, to) {
  return Object.keys(visitFilterArgs(visited, from, to)).length > 0;
}

/** A date the database sends as YYYY-MM-DD (a Singapore date), shown
 *  dd/mm/yyyy without passing through a time zone. */
export function sgDate(d) {
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(String(d ?? ''));
  return m ? `${m[3]}/${m[2]}/${m[1]}` : '—';
}

/** The Singapore day of a moment the database sends as a timestamp (a
 *  reward's given_at; its text is in UTC), shown dd/mm/yyyy. 07:30 on 1 Nov
 *  in Singapore is 23:30 on 31 Oct in UTC, and is the 1st. */
const SG_DAY = new Intl.DateTimeFormat('en-GB', { timeZone: 'Asia/Singapore', day: '2-digit', month: '2-digit', year: 'numeric' });
export function sgDayOf(ts) {
  const t = Date.parse(String(ts ?? ''));
  if (!Number.isFinite(t)) return '—';
  const parts = SG_DAY.formatToParts(new Date(t));
  const part = type => parts.find(p => p.type === type)?.value ?? '';
  return `${part('day')}/${part('month')}/${part('year')}`;
}

/** The same as referral_campaign_standing: the highest tier reached, the next
 *  tier and how many more friends reach it (null when there is none). */
export function tierStanding(count, tiers) {
  const n = Math.max(0, Number(count) || 0);
  const list = [...new Set((tiers ?? []).map(Number).filter(t => Number.isFinite(t) && t > 0))].sort((a, b) => a - b);
  const reached = list.filter(t => t <= n).pop() ?? null;
  const next = list.find(t => t > n) ?? null;
  return { tierReached: reached, nextTier: next, toNext: next == null ? null : next - n };
}

/** "1 Oct – 31 Oct 2026" for a promotion's window. */
export function windowLabel(startsOn, endsOn) {
  const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  const p = d => /^(\d{4})-(\d{2})-(\d{2})/.exec(String(d ?? ''));
  const a = p(startsOn), b = p(endsOn);
  if (!a || !b) return '';
  const fa = `${Number(a[3])} ${MONTHS[Number(a[2]) - 1]}`;
  const fb = `${Number(b[3])} ${MONTHS[Number(b[2]) - 1]} ${b[1]}`;
  return a[1] === b[1] ? `${fa} – ${fb}` : `${fa} ${a[1]} – ${fb}`;
}

/** What the status means, in the report's banner. */
export function statusNote(campaign) {
  if (!campaign) return '';
  const w = windowLabel(campaign.starts_on, campaign.ends_on);
  if (campaign.status === 'final') return `Final: the promotion ran ${w}. Rewards can be marked as given.`;
  if (campaign.status === 'not_started') return `Not started: the promotion runs ${w}.`;
  return `Provisional: the promotion runs ${w}; counts can still change. Rewards are given after it ends, for the highest tier reached.`;
}

/** 404: a referrer's friends referred in the window who have not visited
 *  yet (the Owner, 8 Oct 2026). The report sends it as not_yet_visited; a
 *  database before 404 does not, and then the friends listed without a visit
 *  are counted here. */
export function notYetVisited(row) {
  if (row && row.not_yet_visited != null && Number.isFinite(Number(row.not_yet_visited))) return Number(row.not_yet_visited);
  return (row?.friends ?? []).filter(f => !f?.counted && !f?.first_visit_on).length;
}

/** The line under a referrer's name: their friends referred in the window
 *  who have not visited at all (the only ones the report lists without
 *  counting them). Once the promotion has ended it says they did not visit
 *  during it or since: a friend who first visits after the end is no longer
 *  listed, so the figure is not every friend who missed the promotion. No
 *  line when there are none, so "0 referred" is never read as nobody
 *  referred. */
export function notYetVisitedLine(n, status) {
  const count = Math.max(0, Math.trunc(Number(n)) || 0);
  if (count === 0) return '';
  const who = count === 1 ? '1 friend referred in the window' : `${count} friends referred in the window`;
  return status === 'final'
    ? `${who} did not visit during it or since`
    : `${who} ${count === 1 ? 'has' : 'have'} not visited yet`;
}

/** What the friend table says about a friend (404): counted; not counted
 *  because they have not visited yet, which once the promotion has ended
 *  means they did not visit during it. A database before 404 also listed
 *  friends whose first visit fell outside the window. */
export function friendStatus(friend, status) {
  if (friend?.counted) return 'Yes';
  if (!friend?.first_visit_on) return status === 'final' ? 'No visit during the promotion' : 'Not yet visited';
  return 'Visit outside the window';
}

/** What the referrer table says when it shows nobody (404). With "Only
 *  referrers with a friend counted" ticked, the report can still list
 *  referrers whose friends are all waiting for a first visit, so it does not
 *  say there are none. */
export function emptyReportNote(listed, onlyCounted) {
  if (onlyCounted && Number(listed) > 0) {
    return 'No referrer has a friend counted in this promotion yet. Untick "Only referrers with a friend counted" to see the friends referred during it who have not visited.';
  }
  return 'No friend counts in this promotion yet, and no friend referred during it is waiting for a first visit';
}

/** The affiliate portal's one line about their own progress. */
export function progressLine(p) {
  if (!p || !p.campaign) return '';
  const n = Number(p.counted) || 0;
  const friends = `${n} friend${n === 1 ? '' : 's'} counted`;
  if (p.next_tier == null) return `${friends} — you have reached the top tier (${p.tier_reached}).`;
  const more = Number(p.to_next);
  const reached = p.tier_reached != null ? ` You have reached tier ${p.tier_reached}.` : '';
  return `${friends} — ${more} more to reach ${p.next_tier}.${reached}`;
}

/** 404: the portal's line about the friends the affiliate referred during
 *  the promotion who have not visited the centre yet (not_yet_visited:
 *  counts only, past customers left out by the database). '' when there are
 *  none, when the database does not send the figure (before 404), and once
 *  the promotion has ended: then nothing they do changes that promotion, and
 *  a friend who visited after the end is no longer in the figure. */
export function portalNotYetVisitedLine(p) {
  if (!p || !p.campaign || p.campaign.status === 'final') return '';
  const n = Math.max(0, Math.trunc(Number(p.not_yet_visited)) || 0);
  if (n === 0) return '';
  return n === 1
    ? "1 friend you referred during the promotion hasn't visited yet."
    : `${n} friends you referred during the promotion haven't visited yet.`;
}

/** The reward lines as give_referral_campaign_reward takes them, or the
 *  reason they cannot be sent. One line per product, a whole quantity of at
 *  least 1. Blank lines (no product) are left out. */
export function rewardItems(lines) {
  const out = [];
  const seen = new Set();
  for (const l of lines ?? []) {
    const id = String(l?.product_id ?? '').trim();
    if (!id) continue;
    const q = String(l?.quantity ?? '').trim();
    if (!/^\d+$/.test(q) || Number(q) < 1) return { items: null, error: 'Each product needs a whole quantity of at least 1.' };
    if (seen.has(id)) return { items: null, error: 'Each product goes on one line only.' };
    seen.add(id);
    out.push({ product_id: id, quantity: Number(q) });
  }
  if (out.length === 0) return { items: null, error: 'Choose at least one product and its quantity.' };
  return { items: out, error: null };
}
