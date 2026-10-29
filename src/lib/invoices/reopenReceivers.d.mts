/** One entry of invoice_reopen_preview's credit_receivers (478): what one customer receives. */
export interface ReopenReceiver {
  customer_id: string;
  customer_name: string | null;
  invoice_customer: boolean;
  credit_released_on_reopen: number | string;
  bundle_vouchers_given_on_reopen: number;
  bundle_vouchers_to_choose_on_reopen: number;
  reward_units_given_on_reopen?: number;
  credit_from_settling_payment: number | string;
  bundle_vouchers_from_settling_payment?: number;
  bundle_vouchers_to_choose_from_settling_payment?: number;
  reward_units_from_settling_payment?: number;
  credit_to_reinstate_after_settlement: number | string;
}
/** The keys of invoice_reopen_preview these lines read (478). */
export interface ReopenGives {
  bundle_vouchers_given_on_reopen?: number | null;
  bundle_vouchers_to_choose_on_reopen?: number | null;
  reward_units_given_on_reopen?: number | null;
  credit_from_settling_payment?: number | string | null;
  bundle_vouchers_from_settling_payment?: number | null;
  bundle_vouchers_to_choose_from_settling_payment?: number | null;
  reward_units_from_settling_payment?: number | null;
  credit_receivers?: ReopenReceiver[] | null;
}
/** The line for a bundle's vouchers the reopening gives at once, or null. */
export function reopenVoucherLine(preview: ReopenGives | null | undefined): string | null;
/** The line for a Credit Package's reward units the reopening gives at once, or null. */
export function reopenRewardUnitsLine(preview: ReopenGives | null | undefined): string | null;
/** The line for the credit the payment that settles the invoice gives, or null. */
export function settlingPaymentLine(preview: ReopenGives | null | undefined): string | null;
/** The line for the vouchers the payment that settles the invoice gives (a bundle's and a package's reward units), or null. */
export function settlingVouchersLine(preview: ReopenGives | null | undefined): string | null;
/** The notes naming who receives what, one per customer other than the invoice's. */
export function reopenReceiverNotes(preview: ReopenGives | null | undefined): string[];
