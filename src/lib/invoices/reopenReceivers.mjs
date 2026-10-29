// What reopening an invoice gives, and to whom: the Reopen dialog's lines
// (478).
//
// The Owner's answer E, 27 Oct 2026 ("Dialogs name the receiver"): the
// Reopen dialog shows a Premium Bundle's vouchers the reopening gives at once
// (it settles the invoice there and then), the credit the payment that
// settles the invoice gives (a package's or bundle's paid credit not yet
// released, and its Bonus), and which customer receives what when that is
// not the invoice's customer (after a customer change that kept the
// benefits with whoever holds them, 'keep'; credit an Owner moved to
// someone). And, as the Owner ticked it ("plus the vouchers and extra
// credit the payment will give"): the vouchers the settling payment gives
// (a bundle's free vouchers, chosen at the till or to choose later) and a
// Credit Package's reward units, at once where the reopening settles it,
// else with the settling payment. The server works it all out
// (invoice_reopen_preview: its bundle_vouchers_given_on_reopen,
// bundle_vouchers_to_choose_on_reopen, reward_units_given_on_reopen,
// credit_from_settling_payment, bundle_vouchers_from_settling_payment,
// bundle_vouchers_to_choose_from_settling_payment and
// reward_units_from_settling_payment, and credit_receivers, one entry per
// customer); this module turns that into the words the dialog shows. Kept
// free of React so it is tested with the Node runner.

const money = n => `S$${Number(n || 0).toFixed(2)}`;
const count = n => Math.max(0, Math.trunc(Number(n) || 0));
const vouchers = n => `${n} bundle voucher${n === 1 ? '' : 's'}`;
const units = n => `${n} reward unit${n === 1 ? '' : 's'}`;

/** The parts' names, as a person lists them: 'a', 'a and b', 'a, b and c'. */
function listOf(parts) {
  if (parts.length <= 1) return parts.join('');
  return `${parts.slice(0, -1).join(', ')} and ${parts[parts.length - 1]}`;
}

/**
 * The line for a bundle's vouchers the reopening gives at once (those chosen
 * at the till, and the rest of its free vouchers to choose later), or null
 * when it gives none (before 478 the preview has no such keys).
 */
export function reopenVoucherLine(preview) {
  const given = count(preview?.bundle_vouchers_given_on_reopen);
  const later = count(preview?.bundle_vouchers_to_choose_on_reopen);
  if (given + later <= 0) return null;
  const rest = later <= 0 ? '' : given > 0 ? ` (and ${later} more to choose later)` : ` (${later} to choose later)`;
  return `Bundle vouchers given at once on reopening: ${given}${rest}`;
}

/**
 * The line for a Credit Package's reward units the reopening gives at once
 * (it settles the invoice there and then), or null when it gives none.
 */
export function reopenRewardUnitsLine(preview) {
  const given = count(preview?.reward_units_given_on_reopen);
  if (given <= 0) return null;
  return `Credit Package reward units given at once on reopening: ${given}`;
}

/**
 * The line for the credit the payment that settles the reopened invoice
 * gives (all the payments up to its total, together), or null when it gives
 * none.
 */
export function settlingPaymentLine(preview) {
  const credit = Number(preview?.credit_from_settling_payment || 0);
  if (!(credit > 0)) return null;
  return `Credit the settling payment gives (package or bundle paid credit not yet released, and the Bonus): ${money(credit)}`;
}

/**
 * The line for the vouchers the payment that settles the reopened invoice
 * gives (a bundle's free vouchers, chosen at the till or to choose later,
 * and a Credit Package's reward units), or null when it gives none.
 */
export function settlingVouchersLine(preview) {
  const given = count(preview?.bundle_vouchers_from_settling_payment);
  const later = count(preview?.bundle_vouchers_to_choose_from_settling_payment);
  const reward = count(preview?.reward_units_from_settling_payment);
  const parts = [];
  if (given > 0) parts.push(vouchers(given) + (later > 0 ? ` (and ${later} more to choose later)` : ''));
  else if (later > 0) parts.push(`${vouchers(later)} to choose later`);
  if (reward > 0) parts.push(`${reward} Credit Package reward unit${reward === 1 ? '' : 's'}`);
  if (parts.length === 0) return null;
  return `Vouchers the settling payment gives: ${listOf(parts)}`;
}

/**
 * The notes naming who receives what, one per customer other than the
 * invoice's, in the order the server lists them: [] when everything goes to
 * the invoice's customer (and before 478, when the preview has no
 * receivers).
 */
export function reopenReceiverNotes(preview) {
  const receivers = Array.isArray(preview?.credit_receivers) ? preview.credit_receivers : [];
  const notes = [];
  for (const r of receivers) {
    if (!r || r.invoice_customer) continue;
    const parts = [];
    let plural = false;
    const add = (n, words) => { if (n > 0) { parts.push(words(n)); plural = plural || n > 1; } };
    if (Number(r.credit_released_on_reopen || 0) > 0) parts.push(`${money(r.credit_released_on_reopen)} released at once`);
    add(count(r.bundle_vouchers_given_on_reopen), n => `${vouchers(n)} given at once`);
    add(count(r.bundle_vouchers_to_choose_on_reopen), n => `${vouchers(n)} to choose later`);
    add(count(r.reward_units_given_on_reopen), n => `${units(n)} given at once`);
    if (Number(r.credit_from_settling_payment || 0) > 0) parts.push(`${money(r.credit_from_settling_payment)} from the settling payment`);
    add(count(r.bundle_vouchers_from_settling_payment), n => `${vouchers(n)} from the settling payment`);
    add(count(r.bundle_vouchers_to_choose_from_settling_payment), n => `${vouchers(n)} to choose later from the settling payment`);
    add(count(r.reward_units_from_settling_payment), n => `${units(n)} from the settling payment`);
    if (Number(r.credit_to_reinstate_after_settlement || 0) > 0) parts.push(`${money(r.credit_to_reinstate_after_settlement)} reinstated after settlement`);
    if (parts.length === 0) continue;
    const verb = parts.length > 1 || plural ? 'go' : 'goes';
    notes.push(`${listOf(parts)} ${verb} to ${r.customer_name || 'another customer'}, who holds the benefits, not to this invoice's customer.`);
  }
  return notes;
}
