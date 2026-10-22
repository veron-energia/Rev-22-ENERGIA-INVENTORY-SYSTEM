/** The roles that add and edit customers (418). */
export const CUSTOMER_EDIT_ROLES: readonly string[];
/** True when this role may add customers, edit them and change their phone (418). */
export function canEditCustomers(role: string | null | undefined): boolean;
/** What a role that may not add customers is told. */
export const CUSTOMER_EDIT_REFUSED: string;
/** True when this role sees a customer's full Profile (figures, purchase timeline, phone history) and their Downline (453). */
export function canSeeCustomerProfile(role: string | null | undefined): boolean;
