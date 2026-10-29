// Who receives what a Credit Package or Premium Bundle gives on payment (476).
//
// The Owner's answer E, 27 Oct 2026 ("Dialogs name the receiver"): after a
// customer change that kept the benefits with whoever holds them ('keep'),
// what a package paid in part gives later (the credit each payment
// releases, and at full payment the rest of it, its Bonus and its vouchers)
// goes to the customer who holds its benefits, not to the invoice's new
// customer. The Pay dialog (Record Payment) says so. And on a reopened
// invoice, the credit the payment that settles it reinstates (credit the
// cancellation took back) goes to whoever holds the invoice's benefits, as
// the Reopen dialog says (478; the Owner, 28 Oct 2026: "All of the
// credit"). The server works out whom (invoice_credit_receivers: the lines
// whose receiver is not the invoice's customer, and the credit to reinstate
// by receiver); this module turns that into the words the page shows. Kept
// free of React so it is tested with the Node runner.

const money = n => `S$${Number(n || 0).toFixed(2)}`;

/** The lines' names, as a person lists them: 'A', 'A and B', 'A, B and C'. */
function listOf(names) {
  if (names.length <= 1) return names.join('');
  return `${names.slice(0, -1).join(', ')} and ${names[names.length - 1]}`;
}

/**
 * The notes Record Payment shows, one per receiver: [] when every line's
 * credit goes to the invoice's customer, and when the server's answer was
 * read for another invoice, or for this invoice when it had another customer
 * (Edit Invoice changed it since), so a stale answer is never shown.
 */
export function creditReceiverNotes(receivers, invoice) {
  if (!receivers || !invoice || receivers.invoice_id !== invoice.id
      || (receivers.customer_id ?? null) !== (invoice.customer_id ?? null)) return [];
  const byReceiver = new Map();
  const of = (id, name) => {
    const r = byReceiver.get(id) ?? { name: name || 'another customer', labels: [], back: 0 };
    byReceiver.set(id, r);
    return r;
  };
  for (const line of receivers.lines ?? []) {
    if (!line?.customer_id || line.customer_id === invoice.customer_id) continue;
    of(line.customer_id, line.customer_name).labels.push(line.label || 'this package');
  }
  // 476: the credit the payment that settles a reopened invoice reinstates.
  for (const back of receivers.reinstated ?? []) {
    const amount = Number(back?.amount || 0);
    if (!back?.customer_id || back.customer_id === invoice.customer_id || !(amount > 0)) continue;
    of(back.customer_id, back.customer_name).back += amount;
  }
  return [...byReceiver.values()].map(({ name, labels, back }) => {
    const parts = [];
    if (labels.length > 0) {
      const one = labels.length === 1;
      // "Any": a package may have no Bonus and no vouchers; whatever it has goes along.
      parts.push(`Credit from ${listOf(labels)} goes to ${name}, who holds ${one ? 'its' : 'their'} benefits, `
        + `not to this invoice's customer. Any Bonus or vouchers ${one ? 'it gives' : 'they give'} once paid in full go to ${name} too.`);
    }
    if (back > 0) {
      // "reinstated", as the Reopen dialog calls it (478: "reinstated after settlement")
      parts.push(labels.length > 0
        ? `So does the ${money(back)} of credit reinstated once this invoice is paid in full.`
        : `${money(back)} of credit reinstated once this invoice is paid in full goes to ${name}, `
          + `who holds the benefits, not to this invoice's customer.`);
    }
    return parts.join(' ');
  });
}
