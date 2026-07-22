// Database types — mirror the Supabase schema (Phase 1 subset + forward decls)

export type UserRole = 'owner' | 'admin' | 'manager' | 'inventory_manager' | 'staff';
export type ProductType = 'own' | 'third_party';
export type LocationType = 'warehouse' | 'store';

export interface Profile {
  id: string;
  full_name: string;
  email: string;             // Work Email — this IS the Supabase Auth login address
  personal_email: string | null;
  personal_phone: string | null;
  work_phone: string | null;
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
  phone: string | null;
  is_active: boolean;
  deleted_at: string | null;
  created_at: string;
}

export interface Store {
  id: string;
  name: string;
  code: string;
  address: string | null;
  phone: string | null;
  email: string | null;
  website: string | null;
  co_reg_no: string | null;
  paynow_uen: string | null;
  bank_account: string | null;
  gst_enabled: boolean;
  gst_rate: number;
  company_logo_url: string | null;
  store_logo_url: string | null;
  qr_paynow_url: string | null;
  qr_grabpay_url: string | null;
  qr_atome_url: string | null;
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
  is_important: boolean;
  brand_id: string | null;
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
  | 'inventory_adjustment'
  | 'transfer_dispatch'
  | 'transfer_receipt'
  | 'transfer_discrepancy';

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

export type ApprovalStatus =
  | 'pending' | 'approved' | 'partially_approved' | 'rejected' | 'cancelled'
  // Phase 11 transfer lifecycle
  | 'in_transit' | 'received' | 'received_with_discrepancy' | 'completed';
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
  transfer_dispatch: 'Transfer Dispatch',
  transfer_receipt: 'Transfer Receipt',
  transfer_discrepancy: 'Transfer Discrepancy',
};

export const APPROVAL_STATUS_LABELS: Record<ApprovalStatus, string> = {
  pending: 'Pending',
  approved: 'Approved',
  partially_approved: 'Partially Approved',
  rejected: 'Rejected',
  cancelled: 'Cancelled',
  in_transit: 'In Transit',
  received: 'Received',
  received_with_discrepancy: 'Received — Discrepancy',
  completed: 'Completed',
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
  version?: number;
  edited_at?: string | null;
  edited_by?: string | null;
  edit_count?: number;
  // Phase 11 — dispatch / receipt / discrepancy
  dispatched_at?: string | null;
  received_at?: string | null;
  received_by?: string | null;
  receipt_note?: string | null;
  has_discrepancy?: boolean;
  discrepancy_resolved?: boolean;
  was_partial?: boolean;
}

export interface TransferRequestLine {
  id: string;
  transfer_request_id: string;
  product_id: string;
  quantity: number;
  approved_quantity: number | null;
  created_at: string;
  // Phase 11
  in_transit_quantity?: number | null;
  received_quantity?: number | null;
  discrepancy_quantity?: number | null;
  discrepancy_reason?: string | null;
  discrepancy_resolution?: string | null;
  discrepancy_resolved_at?: string | null;
}

// ── Phase 3: Sales types ─────────────────────────────────────────────────────
export type CustomerGender = 'male' | 'female' | 'other';
export interface Customer {
  id: string;
  full_name: string;
  phone: string;
  email: string | null;
  address: string | null;         // legacy — kept in DB, no longer collected in the form
  date_of_birth: string | null;
  gender: CustomerGender | null;
  gender_other: string | null;
  occupation: string | null;
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
  member_price: number | null;
  non_member_price: number | null;
  eligibility: 'both' | 'member_only' | 'non_member_only';
  is_active: boolean;
  created_at: string;
}

export type InvoiceStatus =
  | 'draft' | 'unpaid' | 'partially_paid' | 'paid'
  | 'cancellation_requested' | 'cancelled' | 'refund_requested' | 'refunded'
  | 'completed_foc';

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
  // Phase 12 — FOC rollups
  has_foc?: boolean;
  is_full_foc?: boolean;
  foc_total?: number;
  foc_confirmed_at?: string | null;
  foc_confirmed_by?: string | null;
  is_topup?: boolean;
  // Phase 13 — exchange invoices
  is_exchange?: boolean;
  exchange_id?: string | null;
  exchange_credit_total?: number;
}

// ── Phase 13: invoice revision history ───────────────────────────────────────
export interface InvoiceRevision {
  id: string;
  invoice_id: string;
  revision_no: number;
  edited_by: string | null;
  edit_reason: string | null;
  edited_at: string;
}

export interface InvoiceItem {
  id: string;
  invoice_id: string;
  product_id: string | null;
  line_kind?: 'product' | 'voucher' | 'promotion' | 'membership' | 'therapy';
  voucher_id?: string | null;
  promotion_id?: string | null;
  line_voucher_id?: string | null;
  line_discount?: number;
  topup_amount?: number;
  quantity: number;
  unit_price: number;
  line_total: number;
  // Phase 4 permanent price snapshots
  price_mode?: 'member' | 'non_member' | null;
  price_source?: string | null;
  price_source_id?: string | null;
  store_id_snapshot?: string | null;
  member_price_snapshot?: number | null;
  non_member_price_snapshot?: number | null;
  original_price?: number | null;
  price_overridden?: boolean;
  override_reason?: string | null;
  override_by?: string | null;
  override_at?: string | null;
  membership_plan_id?: string | null;
  plan_name_snapshot?: string | null;
  plan_months_snapshot?: number | null;
  member_id_snapshot?: string | null;
  // Phase 12 — FOC. `quantity` stays the FULL quantity (stock and
  // entitlements follow it); `line_total` holds the CHARGED value only.
  foc_quantity?: number;
  is_foc?: boolean;
  foc_amount?: number;                 // FOC value BEFORE discounts
  foc_original_unit_price?: number | null;
  foc_reason_id?: string | null;
  foc_reason?: string | null;
  foc_by?: string | null;
  foc_at?: string | null;
}

// ── Phase 12: FOC ────────────────────────────────────────────────────────────
export interface FocReason {
  id: string;
  code: string;
  label: string;
  requires_note: boolean;
  sort_order: number;
  is_active?: boolean;
}

export interface FocSummary {
  from: string;
  to: string;
  invoice_count: number;
  full_foc_invoices: number;
  mixed_foc_invoices: number;
  foc_value: number;
  charged_value: number;
  normal_value: number;
  foc_units: number;
  by_kind: { line_kind: string; foc_value: number; foc_units: number; lines: number }[];
  by_reason: { reason: string; foc_value: number; lines: number }[];
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
  completed_foc: 'Completed (FOC)',
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
  actor_role: string | null;
  module: string | null;
  reason: string | null;
  store_id: string | null;
  ip_address: string | null;
  device_info: string | null;
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

// ── Phase 6C: staff service + commission ─────────────────────────────────────
export interface InvoiceServiceStaff { id: string; invoice_id: string; staff_id: string; created_at: string; }
export interface StaffCommission {
  id: string; invoice_id: string; staff_id: string; store_id: string | null;
  invoice_total: number; share_ratio: number; rate: number; commission_amount: number;
  status: 'earned' | 'reversed' | 'paid'; invoice_paid_date: string | null;
  payout_id: string | null; reversed_at: string | null; reversal_reason: string | null; created_at: string;
}
export interface StaffCommissionPayout {
  id: string; payout_month: string; staff_id: string; total_amount: number;
  payment_method_id: string | null; reference: string | null; notes: string | null;
  status: string; paid_by: string | null; paid_at: string; created_at: string;
}
export const SERVICE_STAFF_ROLES: UserRole[] = ['owner', 'manager', 'staff'];

// ── Spec Phase 1: dropdowns + audit extension ───────────────────────────────
export interface Brand { id: string; name: string; is_active: boolean; deleted_at: string | null; created_at: string; updated_at: string; }
export interface Category { id: string; name: string; is_active: boolean; deleted_at: string | null; created_at: string; updated_at: string; }
export interface Supplier {
  id: string; name: string; contact_person: string | null; phone: string | null; email: string | null;
  address: string | null; notes: string | null; is_active: boolean; deleted_at: string | null; created_at: string; updated_at: string;
}

// ── Spec Phase 3: exchanges ──────────────────────────────────────────────────
export interface ProductExchange {
  id: string; exchange_no: string; original_invoice_id: string; customer_id: string;
  processing_store_id: string; affiliate_id: string | null;
  returned_credit_total: number; replacement_total: number; topup_amount: number; nonrefundable_amount: number;
  status: string; reason: string | null; notes: string | null; created_by: string | null; created_at: string; locked_at: string | null;
}
export interface ProductExchangeItem {
  id: string; exchange_id: string; direction: 'returned' | 'replacement';
  original_invoice_item_id: string | null; product_id: string; quantity: number; unit_price: number; line_total: number;
}

// ── Spec Phase 4: therapy ────────────────────────────────────────────────────
export interface TherapyPackageRule {
  id: string; store_id: string; name: string; qualifying_amount: number;
  entitlement_kind: 'unlimited' | 'voucher'; duration_months: number | null; voucher_qty: number | null;
  activation_deadline_days: number; is_active: boolean; effective_date: string; deleted_at: string | null;
  created_at: string; updated_at: string;
}
export interface TherapyEntitlement {
  id: string; entitlement_no: string; customer_id: string; store_id: string; rule_id: string | null;
  package_name: string; entitlement_kind: 'unlimited' | 'voucher'; duration_months: number | null; voucher_qty: number | null;
  qualifying_amount: number; qualified_value: number; forfeited_value: number;
  activation_deadline: string; status: string; created_by: string | null; created_at: string;
  qualification_group_id: string | null;
}

// ── Spec Phase 4B: beneficiaries, activation, date changes ───────────────────
export type TherapyStatus = 'pending_activation' | 'scheduled' | 'active' | 'ended'
  | 'expired_before_activation' | 'cancelled' | 'suspended';
export interface TherapyBeneficiary {
  id: string; entitlement_id: string; beneficiary_customer_id: string;
  portion_months: number | null; portion_vouchers: number | null;
  activation_date: string | null; ending_date: string | null;
  status: TherapyStatus; activated_by: string | null; activated_at: string | null;
  transferred_from: string | null; transferred_at: string | null;
  cancelled_reason: string | null; created_at: string; updated_at: string;
}
export interface TherapyDateChangeRequest {
  id: string; beneficiary_id: string; field: 'activation_date' | 'ending_date';
  old_value: string | null; new_value: string; reason: string; status: string;
  requested_by: string | null; requested_role: string | null;
  approved_by: string | null; approved_at: string | null; rejection_reason: string | null; created_at: string;
}

// ── Spec Phase 5: health & wellness survey ───────────────────────────────────
export interface SurveyLink {
  id: string; token: string; store_id: string; event_name: string | null;
  is_active: boolean; expires_at: string | null; created_by: string | null; created_at: string;
}
export interface HealthSymptomOption {
  id: string; category: string; label: string; sort_order: number; is_active: boolean;
}
export interface HealthSurvey {
  id: string; survey_no: string; store_id: string; survey_link_id: string | null;
  customer_id: string | null; event_name: string | null;
  full_name: string; date_of_birth: string | null; age: number | null;
  sex: 'male' | 'female' | null; phone: string; email: string | null; occupation: string | null;
  has_medical_condition: boolean | null; drinks_alcohol: boolean | null;
  smokes: boolean | null; on_treatment: boolean | null;
  treatment_list: string | null; others_text: string | null;
  consent_newsletter_email: boolean; consent_marketing_email: boolean;
  consent_marketing_sms: boolean; consent_marketing_phone: boolean;
  signature_data: string | null; signed_date: string | null;
  acidity_result: 'red' | 'green' | 'blue' | null;
  remarks_condition: string | null; remarks_recommendation: string | null;
  reviewed_by: string | null; reviewed_at: string | null; pdf_url: string | null;
  health_goals: string | null;
  submitted_at: string; ip_address: string | null; device_info: string | null;
}



// ── Membership system (Phase 2) ──────────────────────────────────────────────
export interface MembershipPlan {
  id: string; name: string; duration_months: number; description: string | null;
  is_active: boolean; is_complimentary: boolean; is_system: boolean;
  deleted_at: string | null; created_at: string;
}
export interface MembershipPlanStorePrice {
  id: string; plan_id: string; store_id: string; membership_fee: number;
  available_at_store: boolean; is_active: boolean; deleted_at: string | null;
}
export interface CustomerMembership {
  id: string; membership_no: string; customer_id: string; plan_id: string;
  store_id: string | null; member_id: string | null;
  source: 'sale' | 'complimentary' | 'migration' | 'renewal';
  invoice_id: string | null; invoice_item_id: string | null; fee_snapshot: number;
  start_date: string | null; expiry_date: string | null;
  status: 'pending_payment' | 'active' | 'expiring_soon' | 'expired' | 'cancelled' | 'suspended';
  is_complimentary: boolean; is_renewal: boolean; previous_membership_id: string | null;
  activated_at: string | null; cancelled_at: string | null; suspended_at: string | null;
  deleted_at: string | null; created_at: string;
}

export interface AffiliateRow {
  customer_id: string;
  full_name: string;
  phone: string;
  member_id: string | null;
  membership_status: string | null;
  membership_plan: string | null;
  membership_expiry: string | null;
  affiliate_state: string;
  block_reason: string | null;
  store_id: string | null;
  store_name: string | null;
  direct_referrals: number;
  downline: number;
  lifetime_earned: number;
  unpaid_payable: number;
  blocked_commission: number;
  last_commission_date: string | null;
  has_profile: boolean;
  manually_suspended: boolean;
}

export interface UnlimitedTherapyPackage {
  id: string;
  name: string;
  duration_months: number;
  description: string | null;
  is_active: boolean;
  deleted_at: string | null;
  created_at: string;
}

export interface UnlimitedTherapyStorePrice {
  id: string;
  package_id: string;
  store_id: string;
  member_price: number | null;
  non_member_price: number | null;
  available_at_store: boolean;
  deleted_at: string | null;
}

export interface PurchasedTherapyEntitlement {
  id: string;
  entitlement_no: string;
  customer_id: string;
  store_id: string;
  package_id: string;
  invoice_id: string;
  invoice_item_id: string | null;
  package_name: string;
  duration_months: number;
  price_snapshot: number;
  price_mode: string | null;
  purchase_date: string;
  activation_deadline: string;
  scheduled_date: string | null;
  activation_date: string | null;
  expiry_date: string | null;
  status: 'pending_activation' | 'scheduled' | 'active' | 'expired' | 'cancelled' | 'refunded';
  created_at: string;
}
