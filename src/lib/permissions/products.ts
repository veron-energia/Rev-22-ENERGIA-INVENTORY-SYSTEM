/**
 * Who may change products, stores, warehouses and store staff, as the
 * database decides it (420). The screens use these only to show or hide
 * buttons; the database checks every change again.
 *
 * The Owner's answer of 9 Oct 2026 (Q13, option A):
 *   - An Inventory Manager handles warehouse stock and product details (name,
 *     SKU, cost, category, supplier), like an Owner or a Manager. An Admin
 *     looks but does not change.
 *   - Managers put Staff and Inventory Managers on the stores they work at.
 *     Only an Owner changes a Manager's stores. Nobody changes their own.
 */
import type { UserRole } from '../../types';

/** Add and edit products, tick their categories and suppliers, delete and
 *  restore them. Mirrors can_edit_products(). */
export const canEditProducts = (r?: UserRole | null): boolean =>
  r === 'owner' || r === 'manager' || r === 'inventory_manager';

/** The lists of brands, categories and suppliers, and the Important star:
 *  an Owner or a Manager, as before. */
export const canConfigureCatalogue = (r?: UserRole | null): boolean =>
  r === 'owner' || r === 'manager';

/** Add, edit, delete and restore stores and warehouses: an Owner or a
 *  Manager, as before. */
export const canManagePlaces = (r?: UserRole | null): boolean =>
  r === 'owner' || r === 'manager';

/** Owners and Admins work at every store, so they are never put on one. */
export const worksAtEveryStore = (r?: UserRole | null): boolean =>
  r === 'owner' || r === 'admin';

/**
 * Why the caller may not put this person on (or take them off) this store,
 * or null when they may. Mirrors assign_user_store(); the database has the
 * last word.
 *   caller: the signed-in person; callerStoreIds: the stores they work at.
 */
export function storeAssignmentBlock(
  caller: { id: string; role?: UserRole | null },
  target: { id: string; role: UserRole },
  storeId: string,
  callerStoreIds: string[],
): string | null {
  if (!caller.role || !['owner', 'admin', 'manager'].includes(caller.role)) {
    return 'Only an Owner or Manager can change who works at a store.';
  }
  if (target.id === caller.id) return 'You cannot change your own stores. Ask an Owner.';
  if (worksAtEveryStore(target.role)) return 'Owners and Admins work at every store.';
  if (target.role === 'manager' && caller.role !== 'owner') return 'Only an Owner can change a Manager\'s stores.';
  if (caller.role === 'manager' && !callerStoreIds.includes(storeId)) {
    return 'You can only put people on the stores you work at.';
  }
  return null;
}
