/**
 * Who may export the customer list and read colleagues' contact details, as migration 539
 * decides it in the database (security audit of 17 Nov 2026, finding M13; the user's decisions
 * of 25 Nov 2026). The pages use these only to show or hide a button and to ask for the columns
 * they may read; the database checks every call again and its sentence is shown when a refusal
 * gets through (another tab, stale data).
 *
 *   1. Only an Owner or a Manager exports the customer list (the Customers page's Export and
 *      Special Export), through export_customers, which writes one Audit Log entry per export.
 *      An Admin is not an Owner or a Manager.
 *   2. search_customers gives anyone but an Owner or a Manager at most 50 customers a call; an
 *      Inventory Manager gets no customer list. Staff still find and open any customer.
 *   3. A colleague's login email, personal phone and personal email are read only by an Owner or
 *      a Manager (user_admin_list, the Users & Roles page) and by the person themselves
 *      (my_profile_contact_details). A signed-in login reads only the other columns of
 *      public.profiles, so a page names them (PROFILE_COLUMNS) and never asks for select('*').
 */
import type { UserRole } from '../../types';

/** 539 (M13): the sentences the database refuses with. All but `exportKind` are code 42501. */
export const CUSTOMER_LIST_MESSAGES = {
  exportOwnerOrManager: 'Only an Owner or a Manager can export the customer list.',
  exportKind: 'An export is the standard export or the Special Export.',
  searchCap: 'A search returns at most 50 customers at a time.',
  inventoryManager: 'An Inventory Manager does not see the customer list.',
} as const;

/** 539 (M13): who gets a customer list (the Customers page): every staff role but an Inventory Manager. */
export const canSeeCustomerList = (role?: UserRole | null): boolean =>
  role === 'owner' || role === 'admin' || role === 'manager' || role === 'staff';

/** 540 (the user, 25 Nov 2026: "Stock only", "No lending by IM"): the sentences the database
 *  refuses an Inventory Manager with (42501). */
export const INVENTORY_MANAGER_MESSAGES = {
  invoice: 'An Inventory Manager does not make or change invoices.',
  loan: 'An Inventory Manager does not lend stock or take it back.',
  stock: 'An Inventory Manager works with stock only.',
} as const;

/** 540: an Inventory Manager works with stock only: no invoices, exchanges, therapy, affiliates or
 *  customers. Every other staff role as before. */
export const worksWithStockOnly = (role?: UserRole | null): boolean => role === 'inventory_manager';

/** 540: who makes and changes invoices (New Invoice, exchanges): every staff role but an Inventory Manager. */
export const canMakeInvoices = (role?: UserRole | null): boolean =>
  role === 'owner' || role === 'admin' || role === 'manager' || role === 'staff';

/** 540 ("No lending by IM"): who lends stock and takes it back (the server: anyone but an Inventory Manager). */
export const canLendStock = (role?: UserRole | null): boolean =>
  role === 'owner' || role === 'admin' || role === 'manager' || role === 'staff';

/** 539 (M13): the most customers one search_customers call gives anyone but an Owner or a Manager. */
export const SEARCH_CAP = 50;

/** 539 (M13, 25 Nov 2026) rule 1: exporting the customer list. */
export const canExportCustomers = (role?: UserRole | null): boolean => role === 'owner' || role === 'manager';

/** 539 (M13) rule 3: reading colleagues' login email, personal phone and personal email. */
export const canSeeStaffContacts = (role?: UserRole | null): boolean => role === 'owner' || role === 'manager';

/** 539 (M13) rule 3: the columns of public.profiles a signed-in login reads. */
export const PROFILE_COLUMNS = 'id, full_name, role, is_active, deleted_at, created_at, updated_at, work_phone, invitation_status';

/** The two exports, as export_customers names them. */
export type CustomerExportKind = 'standard' | 'special';

/** What the Customers page sends export_customers: its search and filters, and the created
 *  dates chosen in the export window (the page applies those itself; the server records them). */
export function customerExportArgs(
  kind: CustomerExportKind,
  filters: { search: string; source: string; visitArgs: { p_visited?: string; p_visit_from?: string; p_visit_to?: string } },
  range: { from?: string; to?: string } = {},
): Record<string, string | null> {
  const v = filters.visitArgs;
  return {
    p_export: kind,
    p_query: filters.search.trim() || null,
    p_source: filters.source || null,
    p_visited: v.p_visited ?? null,
    p_visit_from: v.p_visit_from ?? null,
    p_visit_to: v.p_visit_to ?? null,
    p_created_from: range.from || null,
    p_created_to: range.to || null,
  };
}

/** 539: export_customers is not on this database yet (the pages go live before 539): PostgREST's
 *  "function not found" (PGRST202), or the database's (42883). The page then pages through
 *  search_customers as before 539. */
export const exportFunctionMissing = (e?: { code?: string } | null): boolean =>
  e?.code === 'PGRST202' || e?.code === '42883';

/** A profile row as a page reads it, with the three contact columns filled from a function
 *  (user_admin_list or my_profile_contact_details) when it gave them, else left empty. */
export function withContacts<T extends { id: string }>(
  row: T,
  contacts?: { email?: string | null; personal_phone?: string | null; personal_email?: string | null } | null,
): T & { email: string; personal_phone: string | null; personal_email: string | null } {
  return {
    ...row,
    email: contacts?.email ?? '',
    personal_phone: contacts?.personal_phone ?? null,
    personal_email: contacts?.personal_email ?? null,
  };
}
