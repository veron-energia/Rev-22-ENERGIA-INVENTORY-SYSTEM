// Who edits customers (418) and who sees a customer's full Profile and
// Downline (453, the Owner, 22 Oct 2026): src/lib/customers/customerRoles.mjs,
// which decides the Customers and Affiliates pages' buttons. The database
// checks the same roles (update_customer, create_customer_quick,
// change_customer_phone; customer_profile_stats, customer_purchase_timeline,
// customer_downline_visits).
//
// Run: node --test scripts/customers/tests/customer-roles.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { CUSTOMER_EDIT_ROLES, canEditCustomers, canSeeCustomerProfile } from '../../../src/lib/customers/customerRoles.mjs';

const ROLES = ['owner', 'admin', 'manager', 'inventory_manager', 'staff'];

test('the full Profile and the Downline: Owner, Admin, Manager and Staff; not an Inventory Manager', () => {
  for (const r of ['owner', 'admin', 'manager', 'staff']) assert.equal(canSeeCustomerProfile(r), true, r);
  assert.equal(canSeeCustomerProfile('inventory_manager'), false);
});

test('no role, or one that is not a staff role, sees the full Profile', () => {
  for (const r of [null, undefined, '', 'affiliate', 'Staff', ' staff', 'owner,manager', 'authenticated']) {
    assert.equal(canSeeCustomerProfile(r), false, String(r));
  }
});

test('the roles that see the full Profile are those that add and edit customers (418)', () => {
  for (const r of ROLES) assert.equal(canSeeCustomerProfile(r), canEditCustomers(r), r);
  assert.deepEqual([...CUSTOMER_EDIT_ROLES], ['owner', 'admin', 'manager', 'staff']);
  assert.ok(Object.isFrozen(CUSTOMER_EDIT_ROLES));
});
