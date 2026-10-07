/**
 * The pages' side of 398: who visited, the downline and the referral
 * promotion. The database decides (customer_centre_visits,
 * referral_campaign_friends, referral_campaign_standing); these helpers shape
 * what the Customers page sends to search_customers, the dates shown, the
 * tier wording and the reward lines, and must agree with it.
 *
 * Run: node --test scripts/referrals/tests/campaign.test.mjs
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { visitFilterArgs, visitFilterActive, sgDate, sgDayOf, tierStanding, windowLabel, statusNote, progressLine, rewardItems }
  from '../../../src/lib/referral/campaign.mjs';

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
