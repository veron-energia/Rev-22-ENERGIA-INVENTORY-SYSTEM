export type Balance = { referrer: string; month: string | null; earned: number; adjustments: number; paid: number; balance: number; review_reason: string | null };
export type Payout = { id: string; referrer_customer_id: string; payout_month: string; total_amount: number; total_tier1: number; total_tier2: number; payment_date: string; payment_method_id: string | null; payment_method_name: string | null; reference: string | null; notes: string | null; status: string; version: number; allocation_state: string; allocation_review_reason: string | null };
export const payoutMoney = (value: number | string) => `S$${Number(value).toFixed(2)}`;
export const unavailableName = (id: string) => `Name unavailable · ${id.slice(0, 8)}`;
export const payoutInRange = (p: Payout, from: string, to: string) => (!from || p.payment_date >= from) && (!to || p.payment_date <= to);
export const payoutExportColumns = (name: (id: string) => string) => [
  { header: 'Payout ID', value: (p: Payout) => p.id }, { header: 'Payment date', value: (p: Payout) => p.payment_date },
  { header: 'Commission month', value: (p: Payout) => p.payout_month.slice(0, 7) },
  { header: 'Affiliate', value: (p: Payout) => name(p.referrer_customer_id) },
  { header: 'Affiliate ID', value: (p: Payout) => p.referrer_customer_id },
  { header: 'Amount', value: (p: Payout) => Number(p.total_amount) },
  { header: 'Tier 1', value: (p: Payout) => Number(p.total_tier1) }, { header: 'Tier 2', value: (p: Payout) => Number(p.total_tier2) },
  { header: 'Method', value: (p: Payout) => p.payment_method_name || 'Historical method unavailable' },
  { header: 'Reference', value: (p: Payout) => p.reference || '' }, { header: 'Notes', value: (p: Payout) => p.notes || '' },
  { header: 'Status', value: (p: Payout) => p.status }, { header: 'Review', value: (p: Payout) => p.allocation_review_reason || '' },
];

