/**
 * 502 (the user, 10 Nov 2026): Legacy Therapy and Qualification, the old
 * same-day spending reward, are gone from every page: Therapy, Invoices,
 * Customers, Reports and the Dashboard. Every record stays in the database;
 * the pages only stop showing it and stop asking for it.
 *
 * What took their place:
 *   - Therapy → "Vouchers to hand over": the vouchers a customer is still owed
 *     from a Credit Package, a Premium Bundle or a therapy package taken as
 *     vouchers. Therapy → "Holidays": the holiday calendars, company closures
 *     and the expiry recalculation preview.
 *   - A Credit Package gives credit only, so its window has no reward section.
 *     A Premium Bundle's free vouchers are not the old reward, and its window
 *     keeps every field, its own "Reward threshold (S$)" too.
 *   - Reports → Therapy keeps the voucher rows and calls them "Reward vouchers"
 *     on screen and in Excel.
 *   - Refunding an older Credit Package sale still opens the reward voucher
 *     review, on the server's new refusal and on its old one.
 * The decisions themselves are in THERAPY_HOLIDAY_AND_REWARDS.md, "Legacy
 * Therapy retired".
 *
 * Source assertions, because what is worth protecting here is an absence: a
 * rendered test shows only what its fixture shows, and an old label or call
 * can come back on a path no fixture takes. The pages themselves are rendered
 * in scripts/therapy/tests/therapy-page-lists.test.mjs, the invoices,
 * customers and reports page tests, and
 * scripts/invoices/tests/reward-review-opens-502.test.mjs.
 *
 * Some things only share the name, and stay (the last test): the Legacy credit
 * wallet (a customer's opening balance), the old FOC-and-voucher line discount
 * 'legacy', and legacy_reward_voucher_options, the till's Premium Bundle
 * voucher picker.
 *
 * Run: node --test scripts/ui/tests/legacy-removed.test.mjs (npm run test:password-ui)
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, existsSync } from 'node:fs';

const repo = path => new URL(`../../../${path}`, import.meta.url);
const read = path => readFileSync(repo(path), 'utf8');

const therapy = read('src/pages/TherapyPage.tsx');
const invoices = read('src/pages/InvoicesPage.tsx');
const customers = read('src/pages/CustomersPage.tsx');
const reports = read('src/pages/ReportsPage.tsx');
const dashboard = read('src/pages/DashboardPage.tsx');
const rewardReview = read('src/components/invoices/InvoiceRewardResolution.tsx');
const financePanel = read('src/components/invoices/InvoiceFinancePanel.tsx');
const guidedAction = read('src/components/invoices/InvoiceGuidedAction.tsx');
const diagnostics = read('src/components/therapy/TherapyDiagnostics.tsx');
const holdings = read('src/components/therapy/CustomerTherapySummary.tsx');
const status = read('src/lib/therapy/status.ts');

/** Every source file under src: its path from src, and its text. */
const srcFiles = readdirSync(repo('src/'), { recursive: true })
  .map(rel => String(rel).replace(/\\/g, '/'))
  .filter(rel => /\.(tsx?|mts|mjs|jsx?|css|json|html)$/.test(rel))
  .map(rel => ({ rel, text: read(`src/${rel}`) }));

/** The lines that match, as "file:line: text". The pattern must not be global. */
const linesMatching = (files, pattern) => files.flatMap(({ rel, text }) =>
  text.split('\n').flatMap((line, i) => (pattern.test(line) ? [`${rel}:${i + 1}: ${line.trim()}`] : [])));

const count = (source, text) => source.split(text).length - 1;

/** The text from `start` (which must be there exactly once) to the first `end` after it. */
function between(source, start, end, what) {
  const at = source.indexOf(start);
  assert.ok(at >= 0, `${what}: "${start}" is not in the source any more; update this test`);
  assert.equal(source.indexOf(start, at + 1), -1, `${what}: "${start}" is in the source more than once`);
  const stop = source.indexOf(end, at + start.length);
  assert.ok(stop > at, `${what}: no "${end}" after "${start}"`);
  return source.slice(at, stop + end.length);
}

/** The 502 migration, when this checkout has it. */
const mig502 = () => readdirSync(repo('supabase/')).find(f => /^502_.*\.sql$/.test(f));

// The functions 502 takes away from signed-in logins, because only Legacy used
// them (its c_revoke), and the four recounts it retires (c_retired: one run by
// hand drops a day's record of which invoices earned a reward). No page may
// call them: they would fail, or worse.
const RETIRED = [
  'affiliate_legacy_day_summary', 'backfill_legacy_qualification', 'claim_legacy_therapy',
  'invoice_legacy_entitlements', 'invoice_therapy_summary', 'legacy_qualification_diagnose',
  'legacy_qualification_group', 'legacy_reward_options', 'legacy_reward_options_diagnostic',
  'legacy_setup_status', 'therapy_map_entitlement_tier', 'therapy_reward_mapping_preview',
  'upsert_legacy_rule',
  'recompute_legacy_qualification', 'recompute_affiliate_legacy_qualification',
  'recompute_affiliates_for_customer_day', 'recompute_legacy_qualification_for_invoice',
];

// The server's refusal to refund or cancel an older Credit Package sale whose
// reward vouchers are still outstanding (assert_invoice_credit_source_evidence):
// since 502, and before it (291). The settlement panel must open the review on
// both: a till still talking to a database before 502, or the other way round.
const REFUSAL_502 = 'This Credit Package came with reward vouchers that are still outstanding. Review them and record '
  + 'what should happen to them, then refund or cancel. Vouchers not handed over yet are withdrawn; those already '
  + 'handed over stay with the customer.';
const REFUSAL_291 = 'This package granted qualification reward entitlements that are still outstanding. Review them '
  + 'and record what should happen to them, then refund or cancel — unclaimed ones are withdrawn and claimed ones '
  + 'keep their history.';
// The other reward texts, which must open no review: since 502 (the review's
// own permission refusal, and the benefit review's note), and before it.
const OTHER_REWARD_TEXTS_502 = [
  'Only an Owner or Manager can settle reward vouchers',
  'This Credit Package came with reward vouchers. Review their original hand-over records first; credit-only '
    + 'allocations cannot complete this purchase.',
];
const OTHER_REWARD_TEXTS_BEFORE = [
  'Only an Owner or Manager can resolve qualification rewards',
  'Qualification rewards require original entitlement and redemption review; credit-only allocations cannot '
    + 'complete this purchase.',
];

test('no page shows Legacy Therapy or Qualification (502)', () => {
  // The Therapy page: not a word of either, in any case. The page still sends
  // the packages' p_reward_qualifying_amount, which this does not match.
  assert.deepEqual(linesMatching([{ rel: 'pages/TherapyPage.tsx', text: therapy }], /legacy|qualification/i), [],
    'the Therapy page names Legacy or Qualification again (a tab, the old list, the old tick or a call)');
  assert.ok(!therapy.includes('therapy_package_rules'), 'the Therapy page reads the qualification rules again');
  assert.deepEqual(RETIRED.filter(name => therapy.includes(name)), [],
    'the Therapy page names a function 502 retires');

  // The Invoices page: the "Legacy therapy earned" box, the same-day working
  // and its hints, the switched-off print block, and the reads behind them.
  const invoiceGone = [
    'detailTherapy', 'invLegacy', 'legacyDiag', 'loadInvoiceLegacy',
    'invoice_legacy_entitlements', 'legacy_qualification_diagnose', 'invoice_therapy_summary',
    'PRINT_THERAPY_BLOCK', 'therapyBlock',
    'Legacy therapy earned', 'Therapy → Legacy Therapy', 'No Legacy therapy from this invoice yet',
    "This invoice hasn't been used for therapy qualification yet",
    '<label>Unlimited Therapy</label>', 'Qualification top-up',
  ];
  assert.deepEqual(invoiceGone.filter(text => invoices.includes(text)), [],
    'the invoice shows the same-day reward again');
  assert.doesNotMatch(invoices, /Legacy [Tt]herapy|[Qq]ualification|same-day paid total/i,
    'nor any of its words');

  // Customers: the old list is never read. Matched exactly, case and all: the
  // wallet's 'legacy' credit category is in the same window and stays.
  assert.ok(!customers.includes('legacy_therapy'), 'the Customers page reads the old reward list again');
  assert.ok(!customers.includes('Legacy therapy'), 'the Customers page shows "Legacy therapy" again');

  // Reports: the word never shows, on screen or in Excel.
  assert.doesNotMatch(reports, /Legacy/, 'Reports says Legacy again');

  // The Dashboard needed no change; it stays that way.
  assert.doesNotMatch(dashboard, /Legacy|[Qq]ualification/, 'the Dashboard says Legacy or Qualification');

  // The Credit Package reward review and the guided Refund / Cancel review.
  assert.doesNotMatch(rewardReview, /Legacy|[Qq]ualification/, 'the reward review says Legacy or qualification again');
  assert.doesNotMatch(guidedAction, /Reward entitlements/, 'the guided review says "Reward entitlements" again');

  // The pieces only the old reward used are gone, and nothing imports them.
  assert.ok(!diagnostics.includes('RewardMappingPreview'), 'TherapyDiagnostics has the reward mapping preview again');
  assert.ok(!status.includes('legacyStatusOn'), 'status.ts has legacyStatusOn again');
  assert.equal(existsSync(repo('src/components/therapy/RewardChoice.tsx')), false, 'RewardChoice.tsx is back');
  // The therapy preview is built by Vite, outside tsconfig's src, so tsc would not see a stale import.
  const preview = ['main.tsx', 'page.tsx'].map(f => ({ rel: `scripts/therapy/preview/${f}`, text: read(`scripts/therapy/preview/${f}`) }));
  assert.deepEqual(linesMatching([...srcFiles, ...preview], /RewardChoice|RewardMappingPreview|legacyStatusOn/), [],
    'something still uses a piece only the old reward used');

  // The holdings card: the old reward's vouchers stay with their customers as
  // ordinary vouchers. Where the server still names their source the old way,
  // the card shows "Earlier reward"; this is the only line that names it.
  assert.deepEqual(linesMatching([{ rel: 'holdings', text: holdings }], /Legacy/).map(l => /OLD_REWARD_SOURCES/.test(l)), [true],
    'the holdings card names Legacy outside its list of the old source names');
  assert.match(holdings, /'Earlier reward'/);
});

test('no file in src says Qualification or Legacy Therapy', () => {
  assert.ok(srcFiles.some(f => f.rel === 'pages/TherapyPage.tsx') && srcFiles.length > 100,
    'the scan of src found its files');
  assert.deepEqual(linesMatching(srcFiles, /Qualification|Legacy [Tt]herapy/), []);
  // "Legacy qualification (reward)" is the old source name as the server may
  // still send it; only the holdings card names it, to show "Earlier reward".
  assert.deepEqual(linesMatching(srcFiles, /Legacy qualification|Legacy rewards?\b/).map(l => l.split(':')[0]),
    ['components/therapy/CustomerTherapySummary.tsx']);
});

test('no page calls a function 502 retires, nor reads the qualification rules', () => {
  // Named anywhere as a string, so a call through a variable is caught too.
  const named = srcFiles.flatMap(({ rel, text }) => RETIRED
    .filter(name => new RegExp(`['"\`]${name}['"\`]`).test(text))
    .map(name => `${rel}: ${name}`));
  assert.deepEqual(named, [], 'a page still calls a retired function');
  assert.deepEqual(linesMatching(srcFiles, /from\(\s*['"`]therapy_package_rules['"`]/), [],
    'a page still reads the qualification rules');
});

test("the retired functions above are 502's own list", t => {
  const file = mig502();
  if (!file) { t.skip('no supabase/502_*.sql in this checkout'); return; }
  const sql = read(`supabase/${file}`);
  const listed = name => {
    const m = sql.match(new RegExp(`${name} constant text\\[\\] := array\\[([\\s\\S]*?)\\];`));
    assert.ok(m, `${file} has no ${name} list any more: update RETIRED in this test`);
    return [...m[1].matchAll(/'([a-z0-9_]+)\(/g)].map(x => x[1]);
  };
  assert.deepEqual([...listed('c_revoke'), ...listed('c_retired')].sort(), [...RETIRED].sort(),
    'RETIRED must be exactly what 502 takes away, so that no page calls any of it');
});

test('the Credit Package window has no reward section; the Premium Bundle window keeps its own', () => {
  // Each window runs from its opening to its </Modal>; neither holds another window.
  const creditWindow = between(therapy, '{pkgForm && (', '</Modal>', 'the Credit Package window');
  const bundleWindow = between(therapy, '{bundleForm && (', '</Modal>', 'the Premium Bundle window');
  assert.match(creditWindow, /'Edit Credit Package' : 'New Credit Package'/);
  assert.match(bundleWindow, /'Edit Premium Bundle' : 'New Premium Bundle'/);
  assert.equal(count(creditWindow, '<Modal'), 1);
  assert.equal(count(bundleWindow, '<Modal'), 1);
  assert.match(creditWindow, /This package issues/, 'the slice is the whole Credit Package window');

  // Gone from the Credit Package window: the threshold, the voucher list, the
  // tick, the Reward units line. It never touches the hidden fields either.
  for (const gone of ['Reward threshold', 'Eligible voucher choices', 'Vouchers listed on this package', 'Also grant',
    'qualification', 'Reward units', 'grants_reward', 'reward_qualifying_amount', 'voucher_ids', 'allVouchers']) {
    assert.ok(!creditWindow.includes(gone), `the Credit Package window has "${gone}" again`);
  }
  // Kept in the Premium Bundle window, exactly as before.
  for (const kept of ['Free vouchers', 'placeholder="auto from payment"', 'Reward threshold (S$)', 'placeholder="994"',
    'Eligible voucher choices *', 'Also grant free reward vouchers']) {
    assert.ok(bundleWindow.includes(kept), `the Premium Bundle window lost "${kept}"`);
  }
  // Nor anywhere else on the page: each of these is the bundle window's own.
  for (const text of ['Reward threshold', 'Eligible voucher choices', 'Also grant']) {
    assert.equal(count(therapy, text), count(bundleWindow, text), `"${text}" is on the page outside the Premium Bundle window`);
  }
  for (const text of ['Reward units', 'Also grant a qualification reward']) {
    assert.ok(!therapy.includes(text), `"${text}" is back on the Therapy page`);
  }

  // The Credit Packages table lost its Reward column; the bundles table keeps its own.
  const creditTable = between(therapy, "{tab === 'credit'", '</table>', 'the Credit Packages tab');
  const bundleTable = between(therapy, "{tab === 'bundles'", '</table>', 'the Premium Bundles tab');
  assert.ok(!creditTable.includes('<th>Reward</th>'), 'the Credit Packages table has a Reward column again');
  assert.ok(!creditTable.includes('grants_reward'), 'the Credit Packages table shows or loads the reward again');
  assert.ok(bundleTable.includes('<th>Reward</th>'), 'the Premium Bundles table lost its Reward column');

  // Every save switches the reward off (a new package's column default is on),
  // and sends the hidden threshold and voucher list back as they were read.
  const creditSave = between(therapy, 'const saveCreditPkg', 'setPkgForm(null); load();', 'the Credit Package save');
  assert.equal(count(creditSave, "rpc('set_catalogue_reward'"), 1);
  assert.match(creditSave,
    /rpc\('set_catalogue_reward',\s*\{\s*p_kind:\s*'credit_package',\s*p_id:\s*data,\s*p_grants:\s*false\s*\}\)/,
    "a Credit Package save must call set_catalogue_reward('credit_package', id, false)");
  assert.ok(!creditSave.includes('grants_reward'), 'the Credit Package save sends a reward tick again');
  assert.match(creditSave, /p_reward_qualifying_amount: pkgForm\.reward_qualifying_amount/);
  assert.match(creditSave, /p_voucher_ids: pkgForm\.voucher_ids/);
});

test('Reports → Therapy keeps the reward voucher rows and calls them Reward vouchers', () => {
  assert.match(reports, /'Reward vouchers'/);
  assert.match(reports, /'Purchased'/);
  // The rows marked is_legacy are the vouchers still owed (since 502 the
  // server leaves the old reward out): they are kept, not filtered out.
  assert.doesNotMatch(reports, /!\s*\w+\.is_legacy/, 'Reports drops the reward voucher rows again');
  // The Type column is on screen and in the Excel export alike.
  const screen = between(reports, "{tab === 'r_therapy' && (", '</table>', 'the Therapy report table');
  const excel = between(reports, "case 'r_therapy':", '] };', 'the Therapy report export');
  assert.match(screen, /<th>Type<\/th>/);
  assert.match(excel, /col\('Type', /);
});

/** The pattern the settlement panel opens the reward review on, read from its source. */
function reviewPattern() {
  const found = [...financePanel.matchAll(/if \(\/((?:\\.|[^/\\\n])+)\/([a-z]*)\.test\(message\)\)\s*setRewardReview\(true\)/g)];
  assert.equal(found.length, 1, 'the panel opens the review on one test of the refusal; if it moved, read it from there');
  assert.equal(count(financePanel, 'setRewardReview(true)'), 1, 'and on nothing else');
  return new RegExp(found[0][1], found[0][2]);
}

test("a refused refund opens the reward review on the server's new words and its old ones", () => {
  const opens = reviewPattern();
  assert.match(REFUSAL_502, opens, "502's refusal must open the review");
  assert.match(REFUSAL_291, opens, 'a database before 502 must still open it');
  for (const text of [...OTHER_REWARD_TEXTS_502, ...OTHER_REWARD_TEXTS_BEFORE]) {
    assert.doesNotMatch(text, opens, `"${text}" is not a refused refund, and must open no review`);
  }
});

test("the refusals above are the server's own words", t => {
  // 'a '\n    'b' is one string, 'a b', in SQL.
  const joined = sql => sql.replace(/'\s*\n\s*'/g, '');
  const quoted = text => `'${text.replace(/'/g, "''")}'`;
  assert.ok(joined(read('supabase/291_invoice_credit_reward_resolution.sql')).includes(`raise exception ${quoted(REFUSAL_291)}`),
    'REFUSAL_291 must be what 291 raises');
  const file = mig502();
  if (!file) { t.skip('no supabase/502_*.sql in this checkout'); return; }
  const sql = joined(read(`supabase/${file}`));
  assert.ok(sql.includes(`raise exception ${quoted(REFUSAL_502)}`), `REFUSAL_502 must be what ${file} raises`);
  for (const text of OTHER_REWARD_TEXTS_502) assert.ok(sql.includes(quoted(text)), `${file} no longer says "${text}"`);
});

test('what replaces them is there', () => {
  // Therapy: Vouchers to hand over for everyone, Holidays for Owners and Managers.
  assert.ok(therapy.includes("'Vouchers to hand over'"), 'the Therapy page has its Vouchers to hand over tab');
  assert.ok(therapy.includes("'Holidays'"), 'the Therapy page has its Holidays tab');
  assert.match(therapy, /rpc\('therapy_list_page'/);
  // Customers: what the customer is still owed, from 502's customer_overview.
  assert.match(customers, /vouchers_to_hand_over/);
  assert.ok(customers.includes('Hand them over on Therapy → Vouchers to hand over.'));
  // The reward review, in plain words.
  assert.ok(rewardReview.includes('This Credit Package came with reward vouchers'));
  assert.ok(guidedAction.includes('Reward vouchers withdrawn (not handed over yet)'));
});

test('what only shares the word stays', () => {
  // The till's Premium Bundle voucher picker, and the old FOC-and-voucher line discount.
  assert.match(invoices, /rpc\('legacy_reward_voucher_options'/);
  assert.match(invoices, /choice === 'legacy'/);
  // The Legacy credit wallet: a customer's opening balance, nothing to do with the reward.
  assert.match(customers, /rpc\('add_legacy_credit'/);
  assert.match(customers, /<option value="legacy">Legacy<\/option>/);
  // Therapy keeps the bundle's reward tick, the holiday calendars and the recalculation preview.
  assert.ok(therapy.includes('Also grant free reward vouchers'));
  assert.ok(therapy.includes('<HolidayAdmin '));
  assert.ok(therapy.includes('<RecalculationPreview '));
  // The Credit Package reward review still opens, for the older sales that need it.
  assert.ok(financePanel.includes('<InvoiceRewardResolution '));
});
