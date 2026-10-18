// 418: who adds and edits customers (the Owner, 9 Oct 2026): Owners,
// Managers and Staff, and the old Admin role. Inventory Managers look after
// stock and products only (Q13); they still find, view and pick customers.
// update_customer, create_customer_quick and change_customer_phone check the
// same in the database, so this only decides which buttons are shown.
export const CUSTOMER_EDIT_ROLES = Object.freeze(['owner', 'admin', 'manager', 'staff']);

/** True when this role may add customers, edit them and change their phone. */
export function canEditCustomers(role) {
  return CUSTOMER_EDIT_ROLES.includes(String(role ?? ''));
}

/** What a role that may not add customers is told. */
export const CUSTOMER_EDIT_REFUSED = 'Only Owners, Managers and Staff can add or change customers. Pick a customer already on the list, or ask one of them.';
