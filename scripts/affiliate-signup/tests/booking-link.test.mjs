/**
 * A new registration through an affiliate's link books with the referrer
 * filled in (392).
 *
 * The referral page sends the person straight to cal.com's free giveaway with
 * their details and "(Referrer) " in the hidden `affiliate` question. cal.com's
 * calendar title for that event type starts with {affiliate}, so the
 * appointment reads "(Jane Tan) John Lim +65…". Every name here is invented.
 *
 * Run: node --test scripts/affiliate-signup/tests/booking-link.test.mjs
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { REFERRAL_BOOKING_PAGE, referralBookingPrefix, referralBookingUrl }
  from '../../../src/lib/referral/bookingLink.mjs';

const read = p => readFileSync(new URL(`../../../${p}`, import.meta.url), 'utf8');
const params = url => Object.fromEntries(new URL(url).searchParams);

test('a registration books on the free giveaway with everything it gave', () => {
  const url = referralBookingUrl({ firstName: ' John ', lastName: 'Lim', email: ' jl@example.invalid ',
    phone: '+6591234567', affiliateLabel: 'Jane Tan' });
  assert.ok(url.startsWith(`${REFERRAL_BOOKING_PAGE}?`));
  assert.equal(REFERRAL_BOOKING_PAGE, 'https://cal.com/energia/free');
  assert.deepEqual(params(url), {
    name: 'John Lim', email: 'jl@example.invalid',
    'WhatsApp-Number': '+6591234567', smsReminderNumber: '+6591234567',
    affiliate: '(Jane Tan) ',
  });
});

test('the referrer keeps its trailing space through the URL', () => {
  // The title template is "{affiliate}{Scheduler} …": the space between the
  // bracket and the customer's name travels in the value itself.
  const url = referralBookingUrl({ firstName: 'John', affiliateLabel: 'Jane Tan' });
  assert.match(url, /affiliate=\(Jane%20Tan\)%20$/);
  assert.equal(params(url).affiliate, '(Jane Tan) ');
});

test('without a referrer there is no affiliate question at all', () => {
  for (const affiliateLabel of [undefined, null, '', '   ', '()', '{ $ }']) {
    const p = params(referralBookingUrl({ firstName: 'John', lastName: 'Lim', affiliateLabel }));
    assert.equal('affiliate' in p, false, `label ${JSON.stringify(affiliateLabel)}`);
    assert.equal(p.name, 'John Lim');
  }
});

test('a referrer is printed as one bracket, whatever came back', () => {
  assert.equal(referralBookingPrefix('Jane Tan'), '(Jane Tan) ');
  assert.equal(referralBookingPrefix('  Jane   Tan '), '(Jane Tan) ');
  assert.equal(referralBookingPrefix('Jane (intern) Tan'), '(Jane intern Tan) ');
  assert.equal(referralBookingPrefix('Tom {Scheduler} $1'), '(Tom Scheduler 1) ');
  assert.equal(referralBookingPrefix("Sean O'Neil"), "(Sean O'Neil) ");
  assert.equal(referralBookingPrefix('Kaur D/O Singh'), '(Kaur D/O Singh) ');
});

test('only a phone that is a real number is filled in', () => {
  assert.equal('WhatsApp-Number' in params(referralBookingUrl({ firstName: 'J', phone: '91234567' })), false);
  assert.equal('smsReminderNumber' in params(referralBookingUrl({ firstName: 'J', phone: '+65123' })), false);
  assert.equal(params(referralBookingUrl({ phone: '+60123456789' }))['WhatsApp-Number'], '+60123456789');
});

test('nothing known is the bare booking page', () => {
  assert.equal(referralBookingUrl(), REFERRAL_BOOKING_PAGE);
  assert.equal(referralBookingUrl({ firstName: ' ', email: '' }), REFERRAL_BOOKING_PAGE);
});

test('characters that mean something in a URL stay inside their value', () => {
  const p = params(referralBookingUrl({ firstName: 'A&B', lastName: 'C=D', email: 'x+y@example.invalid',
    affiliateLabel: 'Ng & Co' }));
  assert.equal(p.name, 'A&B C=D');
  assert.equal(p.email, 'x+y@example.invalid');
  assert.equal(p.affiliate, '(Ng & Co) ');
});

test('the referral page books with the reply\'s referrer and no longer goes to energia.sg/ty', () => {
  const page = read('src/pages/ReferralSignupPage.tsx');
  assert.match(page, /from '\.\.\/lib\/referral\/bookingLink\.mjs'/);
  assert.match(page, /window\.location\.href = referralBookingUrl\(\{[\s\S]*?affiliateLabel: res\?\.affiliate_label,[\s\S]*?\}\);/);
  assert.doesNotMatch(page, /['"`]https:\/\/energia\.sg\/ty/);
  // An existing customer still stays on the page.
  assert.ok(page.indexOf("res?.outcome === 'already_registered'") < page.indexOf('window.location.href = referralBookingUrl'));
});

test('392 answers a new registration with affiliate_label, and the label strips bracketed notes', () => {
  const sql = read('supabase/392_referral_booking_names_the_affiliate.sql');
  assert.match(sql, /''affiliate_label'', \(select public\.affiliate_calendar_label\(c\.full_name\)/);
  assert.match(sql, /'\(\\\(\[\^\(\)\]\*\\\)\|\\\[\[\^\]\[\]\*\\\]\)'/);
});
