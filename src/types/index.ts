// Database types — mirror the Supabase schema (Phase 1 subset + forward decls)

export type UserRole = 'owner' | 'admin' | 'manager' | 'inventory_manager' | 'staff';
export type ProductType = 'own' | 'third_party';
export type LocationType = 'warehouse' | 'store';

export interface Profile {
  id: string;
  full_name: string;
  email: string;
  role: UserRole;
  is_active: boolean;
  deleted_at: string | null;
  created_at: string;
  updated_at: string;
}

export interface Warehouse {
  id: string;
  name: string;
  code: string;
  address: string | null;
  is_active: boolean;
  deleted_at: string | null;
  created_at: string;
}

export interface Store {
  id: string;
  name: string;
  code: string;
  address: string | null;
  is_active: boolean;
  deleted_at: string | null;
  created_at: string;
}

export interface UserStoreAssignment {
  id: string;
  user_id: string;
  store_id: string;
  created_at: string;
}

export interface Product {
  id: string;
  name: string;
  sku: string;
  product_type: ProductType;
  category: string | null;
  brand: string | null;
  uom: string;
  barcode: string | null;
  description: string | null;
  image_url: string | null;
  supplier_name: string | null;
  default_cost_price: number;
  is_active: boolean;
  deleted_at: string | null;
  created_at: string;
  updated_at: string;
}

export interface PaymentMethod {
  id: string;
  name: string;
  is_active: boolean;
  deleted_at: string | null;
  created_at: string;
}

// Role display helpers
export const ROLE_LABELS: Record<UserRole, string> = {
  owner: 'Owner',
  admin: 'Admin',
  manager: 'Manager',
  inventory_manager: 'Inventory Manager',
  staff: 'Staff',
};

// Permission helpers (mirror the SQL helper functions, for UI gating)
export const isOwnerOrAdmin = (r?: UserRole) => r === 'owner' || r === 'admin';
export const isManagerOrAbove = (r?: UserRole) => r === 'owner' || r === 'admin' || r === 'manager';
export const isOwnerOrManager = (r?: UserRole) => r === 'owner' || r === 'manager';
export const canManageWarehouseStock = (r?: UserRole) =>
  r === 'owner' || r === 'manager' || r === 'inventory_manager';

// ── Phase 2: Inventory types ─────────────────────────────────────────────────

export interface WarehouseInventory {
  id: string;
  warehouse_id: string;
  product_id: string;
  current_qty: number;
  low_stock_threshold: number;
  updated_at: string;
}

export interface StoreInventory {
  id: string;
  store_id: string;
  product_id: string;
  current_qty: number;
  low_stock_threshold: number;
  updated_at: string;
}

export type StockMovementType =
  | 'warehouse_stock_in'
  | 'warehouse_to_store'
  | 'warehouse_to_warehouse'
  | 'store_to_store'
  | 'store_sale'
  | 'invoice_cancel_return'
  | 'invoice_refund_return'
  | 'inventory_adjustment';

export interface StockMovement {
  id: string;
  product_id: string;
  movement_type: StockMovementType;
  from_warehouse_id: string | null;
  to_warehouse_id: string | null;
  from_store_id: string | null;
  to_store_id: string | null;
  invoice_id: string | null;
  quantity: number;
  notes: string | null;
  created_by: string | null;
  created_at: string;
}

export type ApprovalStatus = 'pending' | 'approved' | 'partially_approved' | 'rejected' | 'cancelled';
export type TransferType = 'warehouse_to_warehouse' | 'warehouse_to_store' | 'store_to_store';

export interface TransferLine {
  product_id: string;
  quantity: number;
}

export interface ApprovalRequest {
  id: string;
  request_type: string;
  status: ApprovalStatus;
  requested_by: string;
  approved_by: string | null;
  related_record_id: string | null;
  payload: {
    transfer_type?: TransferType;
    source_type?: LocationType;
    source_id?: string;
    dest_type?: LocationType;
    dest_id?: string;
    lines?: TransferLine[];
    approved_lines?: TransferLine[];
    note?: string;
  } | null;
  reason: string | null;
  response_note: string | null;
  rejection_reason: string | null;
  created_at: string;
  approved_at: string | null;
}

export const MOVEMENT_LABELS: Record<StockMovementType, string> = {
  warehouse_stock_in: 'Stock In',
  warehouse_to_store: 'WH → Store',
  warehouse_to_warehouse: 'WH → WH',
  store_to_store: 'Store → Store',
  store_sale: 'Sale',
  invoice_cancel_return: 'Cancel Return',
  invoice_refund_return: 'Refund Return',
  inventory_adjustment: 'Adjustment',
};

export const APPROVAL_STATUS_LABELS: Record<ApprovalStatus, string> = {
  pending: 'Pending',
  approved: 'Approved',
  partially_approved: 'Partially Approved',
  rejected: 'Rejected',
  cancelled: 'Cancelled',
};

// Can create transfer requests (everyone except pure-readonly — all roles here can)
export const canRequestTransfer = (r?: UserRole) =>
  r === 'owner' || r === 'admin' || r === 'manager' || r === 'inventory_manager' || r === 'staff';

// ── Phase 2 FIX: real transfer_requests schema ──────────────────────────────
export interface TransferRequest {
  id: string;
  transfer_type: TransferType;
  source_type: LocationType;
  source_id: string;
  dest_type: LocationType;
  dest_id: string;
  status: ApprovalStatus;
  note: string | null;
  rejection_reason: string | null;
  requested_by: string | null;
  approved_by: string | null;
  created_at: string;
  approved_at: string | null;
  completed_at: string | null;
}

export interface TransferRequestLine {
  id: string;
  transfer_request_id: string;
  product_id: string;
  quantity: number;
  approved_quantity: number | null;
  created_at: string;
}

// ── Phase 3: Sales types ─────────────────────────────────────────────────────
export interface Customer {
  id: string;
  full_name: string;
  phone: string;
  email: string | null;
  address: string | null;
  notes: string | null;
  referred_by: string | null;
  is_referrer: boolean;
  is_active: boolean;
  deleted_at: string | null;
  created_at: string;
}

export interface Affiliate {
  id: string;
  name: string;
  phone: string | null;
  email: string | null;
  customer_id: string | null;
  commission_type: string;     // 'percentage'
  commission_value: number;
  is_active: boolean;
  deleted_at: string | null;
  created_at: string;
}

export interface StoreProductPrice {
  id: string;
  store_id: string;
  product_id: string;
  selling_price: number;
  is_active: boolean;
  created_at: string;
}

export type InvoiceStatus =
  | 'draft' | 'unpaid' | 'partially_paid' | 'paid'
  | 'cancellation_requested' | 'cancelled' | 'refund_requested' | 'refunded';

export interface Invoice {
  id: string;
  invoice_no: string;
  store_id: string;
  customer_id: string;
  affiliate_id: string | null;
  created_by: string;
  status: InvoiceStatus;
  subtotal: number;
  discount_total: number;
  total_amount: number;
  paid_amount: number;
  created_at: string;
  paid_at: string | null;
  locked_at: string | null;
  deleted_at?: string | null;
}

export interface InvoiceItem {
  id: string;
  invoice_id: string;
  product_id: string | null;
  line_kind?: 'product' | 'voucher' | 'promotion';
  voucher_id?: string | null;
  promotion_id?: string | null;
  line_voucher_id?: string | null;
  line_discount?: number;
  topup_amount?: number;
  quantity: number;
  unit_price: number;
  line_total: number;
}

export interface InvoicePayment {
  id: string;
  invoice_id: string;
  payment_method_id: string;
  amount: number;
  payment_reference: string | null;
  received_by: string;
  created_at: string;
  locked_at: string;
}

export interface AffiliateCommission {
  id: string;
  affiliate_id: string;
  invoice_id: string;
  commission_amount: number;
  status: string;   // 'earned' | 'reversed' | 'cancelled'
  created_at: string;
  reversed_at: string | null;
}

export const INVOICE_STATUS_LABELS: Record<InvoiceStatus, string> = {
  draft: 'Draft',
  unpaid: 'Unpaid',
  partially_paid: 'Partially Paid',
  paid: 'Paid',
  cancellation_requested: 'Cancellation Requested',
  cancelled: 'Cancelled',
  refund_requested: 'Refund Requested',
  refunded: 'Refunded',
};

// ── Phase 4: Controls types ──────────────────────────────────────────────────
export interface AuditLog {
  id: string;
  table_name: string;
  record_id: string | null;
  action: string;
  old_data: any;
  new_data: any;
  changed_by: string | null;
  created_at: string;
}

export interface AdjustmentRequest {
  id: string;
  request_type: string;
  status: ApprovalStatus;
  requested_by: string;
  approved_by: string | null;
  related_record_id: string | null;
  reason: string | null;
  response_note: string | null;
  payload: {
    location_type?: LocationType;
    location_id?: string;
    product_id?: string;
    current_qty?: number;
    new_qty?: number;
    difference?: number;
    reference?: string;
    invoice_id?: string;
    invoice_no?: string;
    return_stock?: boolean;
  } | null;
  created_at: string;
  approved_at: string | null;
}

// ── Phase 5B: Two-tier commission types ──────────────────────────────────────
export interface Commission {
  id: string;
  invoice_id: string;
  invoice_item_id: string | null;
  buyer_customer_id: string;
  referrer_customer_id: string;
  tier: 'tier1' | 'tier2';
  product_type: string | null;
  line_amount: number;
  rate: number;
  commission_amount: number;
  status: 'earned' | 'paid' | 'reversed' | 'cancelled';
  payout_id: string | null;
  invoice_paid_date: string | null;
  reversal_reason: string | null;
  created_at: string;
  reversed_at: string | null;
}

export interface CommissionPayout {
  id: string;
  payout_month: string;
  referrer_customer_id: string;
  total_tier1: number;
  total_tier2: number;
  total_amount: number;
  payment_method_id: string | null;
  reference: string | null;
  notes: string | null;
  status: string;
  paid_by: string | null;
  paid_at: string;
  created_at: string;
}

// ── Phase 5C: Voucher types ──────────────────────────────────────────────────
export type VoucherKind = 'normal' | 'fixed_discount' | 'percentage_discount';
export type VoucherQtyType = 'unlimited' | 'limited';

export interface Voucher {
  id: string;
  name: string;
  code: string;
  voucher_kind: VoucherKind;
  discount_amount: number | null;
  discount_percent: number | null;
  max_discount_cap: number | null;
  qty_type: VoucherQtyType;
  selling_price: number;
  valid_from: string | null;
  valid_until: string | null;
  is_active: boolean;
  description: string | null;
  terms: string | null;
  deleted_at: string | null;
  created_at: string;
}

export interface VoucherStoreStock {
  id: string;
  voucher_id: string;
  store_id: string;
  current_qty: number;
  updated_at: string;
}

export const VOUCHER_KIND_LABELS: Record<VoucherKind, string> = {
  normal: 'Normal (sellable)',
  fixed_discount: 'Fixed Amount Discount',
  percentage_discount: 'Percentage Discount',
};

// ── Phase 5D: Promotion types ────────────────────────────────────────────────
export type PromotionType = 'bundle' | 'treatment' | 'other';
export type PromotionItemType = 'product' | 'voucher' | 'promotion' | 'treatment';

export interface Promotion {
  id: string;
  name: string;
  code: string;
  promo_type: PromotionType;
  fixed_price: number;
  start_date: string | null;
  end_date: string | null;
  is_active: boolean;
  description: string | null;
  terms: string | null;
  deleted_at: string | null;
  created_at: string;
}

export interface PromotionItem {
  id: string;
  promotion_id: string;
  item_type: PromotionItemType;
  product_id: string | null;
  voucher_id: string | null;
  child_promotion_id: string | null;
  treatment_name: string | null;
  quantity: number;
  notes: string | null;
  created_at: string;
}

export const PROMO_TYPE_LABELS: Record<PromotionType, string> = {
  bundle: 'Bundle', treatment: 'Treatment Package', other: 'Other',
};

// ── Phase 5D-3: Choice groups ────────────────────────────────────────────────
export interface PromotionChoiceGroup {
  id: string;
  promotion_id: string;
  label: string;
  item_kind: 'product' | 'voucher';
  choose_qty: number;
  created_at: string;
}

export interface PromotionChoiceOption {
  id: string;
  group_id: string;
  product_id: string | null;
  voucher_id: string | null;
  created_at: string;
}

// ── Phase 5E: Special products & rentals ─────────────────────────────────────
export type SpecialRateType = 'day' | 'week' | 'month' | 'year';
export type RentalStatus = 'draft' | 'paid' | 'active' | 'returned' | 'overdue' | 'cancelled';
export type ReturnCondition = 'good' | 'damaged' | 'lost';

export interface SpecialProduct {
  id: string; name: string; sku: string; description: string | null;
  sale_price: number; rate_day: number; rate_week: number; rate_month: number; rate_year: number;
  late_fee_per_day: number; is_active: boolean; deleted_at: string | null; created_at: string;
}
export interface SpecialProductStock {
  id: string; special_product_id: string; warehouse_id: string; current_qty: number; updated_at: string;
}
export interface SpecialSale {
  id: string; sale_no: string; special_product_id: string; warehouse_id: string;
  customer_id: string | null; quantity: number; unit_price: number; total_amount: number;
  payment_method_id: string | null; payment_reference: string | null; notes: string | null;
  status: string; stock_returned: boolean | null; sold_by: string | null;
  created_at: string; cancelled_at: string | null;
}
export interface Rental {
  id: string; rental_no: string; special_product_id: string; warehouse_id: string; customer_id: string;
  quantity: number; rate_type: SpecialRateType; rate_amount: number; periods: number; rental_fee: number;
  start_date: string; expected_return_date: string; status: RentalStatus;
  payment_method_id: string | null; payment_reference: string | null;
  paid_at: string | null; activated_at: string | null; returned_at: string | null;
  return_condition: ReturnCondition | null; stock_returned: boolean | null;
  late_days: number; late_fee_per_day: number; late_fee_total: number;
  late_payment_method_id: string | null; late_payment_reference: string | null;
  notes: string | null; created_by: string | null; created_at: string; cancelled_at: string | null;
}
export const RATE_TYPE_LABELS: Record<SpecialRateType, string> = { day: 'Per Day', week: 'Per Week', month: 'Per Month', year: 'Per Year' };
export const RENTAL_STATUS_LABELS: Record<RentalStatus, string> = { draft: 'Draft', paid: 'Paid', active: 'Active', returned: 'Returned', overdue: 'Overdue', cancelled: 'Cancelled' };
