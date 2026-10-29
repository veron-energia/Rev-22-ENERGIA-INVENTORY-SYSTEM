/** One line of invoice_credit_receivers(): its credit goes to this customer. */
export interface CreditReceiverLine {
  invoice_item_id: string;
  label: string | null;
  customer_id: string;
  customer_name: string | null;
}
/** Credit the payment that settles a reopened invoice reinstates for this customer. */
export interface CreditReinstated {
  customer_id: string;
  customer_name: string | null;
  amount: number | string;
}
/** invoice_credit_receivers() (476). */
export interface CreditReceivers {
  invoice_id?: string;
  customer_id?: string | null;
  lines?: CreditReceiverLine[];
  reinstated?: CreditReinstated[];
}
/** Record Payment's notes, one per receiver; [] when there is nothing to say. */
export function creditReceiverNotes(
  receivers: CreditReceivers | null | undefined,
  invoice: { id: string; customer_id?: string | null } | null | undefined,
): string[];
