/**
 * The pages' side of 398 and 404: who visited, the downline and the referral
 * promotion. The database decides (customer_centre_visits,
 * referral_campaign_friends, referral_campaign_standing); these helpers shape
 * what the Customers page sends to search_customers, the dates shown, the
 * tier wording, the friends not yet visited and the reward lines, and must
 * agree with it.
 *
 * Run: node --test scripts/referrals/tests/campaign.test.mjs
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { visitFilterArgs, visitFilterActive, sgDate, sgDayOf, tierStanding, windowLabel, statusNote, progressLine, rewardItems,
  notYetVisited, notYetVisitedLine, friendStatus, portalNotYetVisitedLine, emptyReportNote } from '../../../src/lib/referral/campaign.mjs';

const read = p => readFileSync(new URL(`../../../${p}`, import.meta.url), 'utf8');

test('no visit filter sends nothing: the four-argument call the page always made', () => {
  assert.deepEqual(visitFilterArgs('', '', ''), {});
  assert.deepEqual(visitFilterArgs(undefined, null, undefined), {});
  assert.equal(visitFilterActive('', '', ''), false);
});

test('Visited / Not visited and the first-visit range', () => {
  assert.deepEqual(visitFilterArgs('visited', '', ''), { p_visited: 'visited' });
  assert.deepEqual(visitFilterArgs('visited', '2026-10-01', '2026-10-31'),
    { p_visited: 'visited', p_visit_from: '2026-10-01', p_visit_to: '2026-10-31' });
  assert.deepEqual(visitFilterArgs('', '2026-10-01', ''), { p_visit_from: '2026-10-01' });
  // Not visited has no first visit: its dates are dropped, not sent.
  assert.deepEqual(visitFilterArgs('not_visited', '2026-10-01', '2026-10-31'), { p_visited: 'not_visited' });
  // Anything else is All; a malformed date is no filter.
  assert.deepEqual(visitFilterArgs('yes', '1/10/2026', '2026-13'), {});
  assert.equal(visitFilterActive('not_visited', '', ''), true);
  assert.equal(visitFilterActive('', '', '2026-10-31'), true);
});

test('a Singapore date is shown as it is, with no time zone shift', () => {
  assert.equal(sgDate('2026-10-05'), '05/10/2026');
  assert.equal(sgDate('2026-10-31T23:59:00+08:00'), '31/10/2026');
  assert.equal(sgDate(null), '—');
  assert.equal(sgDate(''), '—');
});

test('a timestamp (a reward given) is shown as its Singapore day, not its UTC day', () => {
  // 07:30 on 1 Nov in Singapore is 23:30 on 31 Oct in UTC, as the database's JSON gives it.
  assert.equal(sgDayOf('2026-10-31T23:30:00+00:00'), '01/11/2026');
  assert.equal(sgDayOf('2026-10-31T15:59:59+00:00'), '31/10/2026');
  assert.equal(sgDayOf('2026-11-01T07:30:00+08:00'), '01/11/2026');
  assert.equal(sgDayOf(null), '—');
  assert.equal(sgDayOf('not a date'), '—');
  // The pages use it for given_at, not the first ten characters.
  for (const p of ['src/components/referrals/ReferralPromotionPanel.tsx', 'src/pages/AffiliateNetworkPage.tsx']) {
    const src = read(p);
    assert.doesNotMatch(src, /given_at\.slice\(0, 10\)/, p);
    assert.match(src, /sgDayOf\((r\.reward\.given_at|p\.reward_given_at)\)/, p);
  }
});

test('the tier reached is the highest at or below the count, as referral_campaign_standing', () => {
  const T = [10, 20, 50, 80];
  const cases = [[0, null, 10, 10], [9, null, 10, 1], [10, 10, 20, 10], [19, 10, 20, 1],
                 [20, 20, 50, 30], [55, 50, 80, 25], [80, 80, null, null], [120, 80, null, null]];
  for (const [n, reached, next, more] of cases) {
    assert.deepEqual(tierStanding(n, T), { tierReached: reached, nextTier: next, toNext: more }, `${n} friends`);
  }
  // Order and duplicates do not matter.
  assert.deepEqual(tierStanding(25, [50, 20, 10, 20, 80]), { tierReached: 20, nextTier: 50, toNext: 25 });
  // The SQL test checks the database with the same table (section 8).
  const sql = read('scripts/referrals/tests/visits-and-october.sql');
  assert.match(sql, /\(0, null, 10, 10\), \(9, null, 10, 1\), \(10, 10, 20, 10\), \(19, 10, 20, 1\),\s+\(20, 20, 50, 30\), \(55, 50, 80, 25\), \(80, 80, null, null\), \(120, 80, null, null\)/);
});

test('the window and the status read plainly', () => {
  assert.equal(windowLabel('2026-10-01', '2026-10-31'), '1 Oct – 31 Oct 2026');
  assert.equal(windowLabel('2026-12-15', '2027-01-14'), '15 Dec 2026 – 14 Jan 2027');
  const c = { code: '2026-10', title: 'October referral promotion', starts_on: '2026-10-01', ends_on: '2026-10-31', tiers: [10, 20, 50, 80] };
  assert.match(statusNote({ ...c, status: 'provisional' }), /^Provisional: .*1 Oct – 31 Oct 2026.*after it ends, for the highest tier reached/);
  assert.match(statusNote({ ...c, status: 'final' }), /^Final: .*Rewards can be marked as given/);
  assert.match(statusNote({ ...c, status: 'not_started' }), /^Not started/);
});

test("the affiliate's own progress line names no one", () => {
  const campaign = { code: '2026-10', title: 'October referral promotion', starts_on: '2026-10-01', ends_on: '2026-10-31', tiers: [10, 20, 50, 80], status: 'provisional' };
  assert.equal(progressLine({ campaign, counted: 3, tier_reached: null, next_tier: 10, to_next: 7 }), '3 friends counted — 7 more to reach 10.');
  assert.equal(progressLine({ campaign, counted: 1, tier_reached: null, next_tier: 10, to_next: 9 }), '1 friend counted — 9 more to reach 10.');
  assert.equal(progressLine({ campaign, counted: 23, tier_reached: 20, next_tier: 50, to_next: 27 }),
    '23 friends counted — 27 more to reach 50. You have reached tier 20.');
  assert.equal(progressLine({ campaign, counted: 81, tier_reached: 80, next_tier: null, to_next: null }),
    '81 friends counted — you have reached the top tier (80).');
  assert.equal(progressLine({ campaign: null }), '');
});

test('404: the friends not yet visited, from the report or (before 404) from the friends listed', () => {
  const friends = [{ counted: true, first_visit_on: '2026-10-05' }, { counted: false, first_visit_on: null },
                   { counted: false, first_visit_on: null }, { counted: false, first_visit_on: '2026-09-20' }];
  assert.equal(notYetVisited({ not_yet_visited: 2, friends }), 2);
  assert.equal(notYetVisited({ not_yet_visited: 0, friends }), 0, 'the database\'s 0 is kept');
  // A database before 404 sends no not_yet_visited (and listed friends who visited outside the window).
  assert.equal(notYetVisited({ friends }), 2);
  assert.equal(notYetVisited({ not_yet_visited: null, friends: [] }), 0);
  assert.equal(notYetVisited(null), 0);
  assert.equal(notYetVisitedLine(2, 'provisional'), '2 friends referred in the window have not visited yet');
  assert.equal(notYetVisitedLine(1, 'not_started'), '1 friend referred in the window has not visited yet');
  assert.equal(notYetVisitedLine('3', 'provisional'), '3 friends referred in the window have not visited yet');
  // After the end the figure is the friends with no visit at all (one who first visits after it is no longer listed).
  assert.equal(notYetVisitedLine(3, 'final'), '3 friends referred in the window did not visit during it or since');
  assert.equal(notYetVisitedLine(1, 'final'), '1 friend referred in the window did not visit during it or since');
  // None: no line, so a referrer counted only for friends referred earlier never reads "0 referred in the window".
  assert.equal(notYetVisitedLine(0, 'provisional'), '');
  assert.equal(notYetVisitedLine(0, 'final'), '');
  assert.equal(notYetVisitedLine(undefined, 'provisional'), '');
  assert.equal(notYetVisitedLine(-1, 'provisional'), '');
});

test('404: a friend is counted, not yet visited, or (after the promotion) did not visit during it', () => {
  assert.equal(friendStatus({ counted: true, first_visit_on: '2026-10-05' }, 'provisional'), 'Yes');
  assert.equal(friendStatus({ counted: true, first_visit_on: '2026-10-05' }, 'final'), 'Yes');
  assert.equal(friendStatus({ counted: false, first_visit_on: null }, 'provisional'), 'Not yet visited');
  assert.equal(friendStatus({ counted: false, first_visit_on: null }, 'not_started'), 'Not yet visited');
  assert.equal(friendStatus({ counted: false, first_visit_on: null }, 'final'), 'No visit during the promotion');
  // Only a database before 404 lists a friend whose first visit fell outside the window.
  assert.equal(friendStatus({ counted: false, first_visit_on: '2026-09-20' }, 'provisional'), 'Visit outside the window');
});

test('404: an empty referrer table never says nobody is waiting while the filter hides them', () => {
  const none = 'No friend counts in this promotion yet, and no friend referred during it is waiting for a first visit';
  assert.equal(emptyReportNote(0, false), none);
  assert.equal(emptyReportNote(0, true), none, 'an empty report, filter or not');
  // The filter hides every referrer listed: their friends are all waiting for a first visit.
  const hidden = emptyReportNote(3, true);
  assert.notEqual(hidden, none);
  assert.match(hidden, /^No referrer has a friend counted in this promotion yet\./);
  assert.match(hidden, /Untick "Only referrers with a friend counted"/);
  assert.doesNotMatch(hidden, /no friend referred during it is waiting/);
  assert.equal(emptyReportNote(3, false), none, 'not filtered: only reached with nobody listed');
});

test('404: the rule as the pages state it is the first visit, whenever the friend was referred', () => {
  const panel = read('src/components/referrals/ReferralPromotionPanel.tsx');
  const flat = panel.replace(/\s+/g, ' ');
  assert.match(flat, /A Tier 1 friend counts when their first visit to the centre is in the promotion, whenever they were referred \(the referral must be recorded by its last day;/);
  assert.match(flat, /Friends referred during the promotion who have not visited yet are listed too, not counted\./);
  assert.doesNotMatch(flat, /referred in the window \(links without|first visited the centre in the same window/, 'the 398 rule is gone');
  assert.doesNotMatch(panel, /r\.referred_in_window/, 'the page reads the not-yet-visited figure, not referred_in_window');
  assert.match(panel, /header: 'Referred In Window, Not Yet Visited', value: r => notYetVisited\(r\)/);
  const portal = read('src/pages/AffiliateNetworkPage.tsx').replace(/\s+/g, ' ');
  assert.match(portal, /A friend counts when their first visit to the centre is during the promotion, whenever you referred them, as long as you referred them by its last day\./);
  assert.doesNotMatch(portal, /when you referred them during the promotion and they visited the centre during it too/);
});

test('404: past customers and the day a form was sent, as the pages state them', () => {
  const flat = read('src/components/referrals/ReferralPromotionPanel.tsx').replace(/\s+/g, ' ');
  assert.match(flat, /A past customer \(a paid or part-paid invoice dated before the promotion started\) is neither counted nor listed; cancelled, refunded, unpaid and FOC invoices do not make one\./);
  assert.match(flat, /A visit through the centre's QR link counts on the day the form was sent, not the date written on it, so a friend's first visit here can differ from the Customers page\./);
  assert.match(flat, />First visit \(promotion\)</);
  const portal = read('src/pages/AffiliateNetworkPage.tsx').replace(/\s+/g, ' ');
  assert.match(portal, /Friends who were already paying customers before it started do not count\./);
});

test('404: the portal says how many friends referred during the promotion have not visited yet, counts only', () => {
  const p = (n, status = 'provisional') => ({ campaign: { code: '2026-10', title: 'October', starts_on: '2026-10-01',
    ends_on: '2026-10-31', tiers: [10, 20], status }, counted: 3, not_yet_visited: n });
  assert.equal(portalNotYetVisitedLine(p(2)), "2 friends you referred during the promotion haven't visited yet.");
  assert.equal(portalNotYetVisitedLine(p(1)), "1 friend you referred during the promotion hasn't visited yet.");
  assert.equal(portalNotYetVisitedLine(p('3')), "3 friends you referred during the promotion haven't visited yet.");
  assert.equal(portalNotYetVisitedLine(p(0)), '', 'hidden at 0');
  assert.equal(portalNotYetVisitedLine(p(-1)), '');
  assert.equal(portalNotYetVisitedLine(p(undefined)), '', 'a database before 404 sends no figure');
  assert.equal(portalNotYetVisitedLine(p(null)), '');
  // After the end the affiliate can do nothing about that promotion, and a friend who visited since is not in the figure.
  assert.equal(portalNotYetVisitedLine(p(2, 'final')), '', 'hidden once the promotion has ended');
  assert.equal(portalNotYetVisitedLine({ campaign: null, not_yet_visited: 2 }), '');
  assert.equal(portalNotYetVisitedLine(null), '');
});

test('reward lines: one per product, a whole quantity of at least 1', () => {
  assert.deepEqual(rewardItems([{ product_id: 'p1', quantity: '2' }, { product_id: '', quantity: '1' }, { product_id: 'p2', quantity: 1 }]),
    { items: [{ product_id: 'p1', quantity: 2 }, { product_id: 'p2', quantity: 1 }], error: null });
  assert.match(rewardItems([{ product_id: '', quantity: '1' }]).error, /at least one product/);
  assert.match(rewardItems([{ product_id: 'p1', quantity: '0' }]).error, /whole quantity of at least 1/);
  assert.match(rewardItems([{ product_id: 'p1', quantity: '1.5' }]).error, /whole quantity/);
  assert.match(rewardItems([{ product_id: 'p1', quantity: '1' }, { product_id: 'p1', quantity: '2' }]).error, /one line only/);
});

test('the pages call the 398 functions, and the Customers page sends the filters to the list and the exports', () => {
  const customers = read('src/pages/CustomersPage.tsx');
  assert.equal((customers.match(/\.\.\.visitArgs,/g) ?? []).length, 2, 'the list and the export both carry the visit filters');
  assert.equal((customers.match(/header: 'First Visit'/g) ?? []).length, 2, 'both exports have the first visit');
  assert.match(customers, /canComplete && <button[^>]*title="Downline: Tier 1 and Tier 2, with visits"/, 'the row\'s Downline is Owner/Manager');
  const affiliates = read('src/pages/AffiliatesPage.tsx');
  assert.match(affiliates, /canManage && view === 'promotion' && <ReferralPromotionPanel isOwner=\{canUnlink\} \/>/);
  assert.match(read('src/components/referrals/DownlineModal.tsx'), /rpc\('customer_downline_visits'/);
  const panel = read('src/components/referrals/ReferralPromotionPanel.tsx');
  for (const fn of ['referral_campaign_report', 'give_referral_campaign_reward', 'void_referral_campaign_reward']) {
    assert.match(panel, new RegExp(`rpc\\('${fn}'`), fn);
  }
  assert.match(read('src/pages/AffiliateNetworkPage.tsx'), /portalRpc<PortalProgress>\('affiliate_portal_campaign_progress'\)/);
});
