-- 400_stock_loan_movement_types.sql
--
-- WHAT THIS IS FOR (the Owner, 6 Oct 2026)
--
-- Stock can now be lent out from a store or a warehouse (a "Lend" button on
-- both stock pages) and taken back later, in part or in full, into any store
-- or warehouse. Lent stock leaves the location's on-hand stock when it goes
-- out, so it cannot be sold, and comes back into the location staff choose
-- when it is returned. Each of those is a stock movement, and Stock History
-- shows them as "Lent out" and "Loan returned". The movements need types of
-- their own: none of the thirteen there today says what happened (the
-- rentals' put-back reuses invoice_cancel_return, which is not copied here).
-- 401 builds the loans on them.
--
-- WHAT THIS DOES
--
--   * Adds 'loan_out' (stock lent out, from the store or warehouse it was
--     lent from) and 'loan_return' (stock taken back, into the store or
--     warehouse staff choose) to stock_movement_type, after the thirteen
--     there today: warehouse_stock_in, warehouse_to_store,
--     warehouse_to_warehouse, store_to_store, store_sale,
--     invoice_cancel_return, invoice_refund_return, inventory_adjustment,
--     exchange_return_in, exchange_replacement_out, transfer_dispatch,
--     transfer_receipt, transfer_discrepancy.
--
-- It is a migration of its own because a value added to an enum cannot be
-- used in the transaction that added it: 401 and the app use them only after
-- this one is committed. Apply 400, then 401.
--
-- NOT CHANGED
--
--   * Every existing movement, and every function. Nothing writes the new
--     types until 401 is applied, and then only lend_stock and
--     return_stock_loan do. The functions that name movement types (the
--     invoice ones key on invoice_id and name store_sale and the two invoice
--     returns; transfers and Stock History's transit name the transfer
--     types) pass the new ones by, and stock_history_effect counts them as
--     any movement with a source or a destination: minus at the source, plus
--     at the destination. 401 has the review.
--
-- SAFETY
--
-- Two statements that do nothing when the values are already there, so a
-- re-run changes nothing. An enum value cannot be removed again once
-- committed (there is no ALTER TYPE ... DROP VALUE); an unused value is
-- harmless. The check after them confirms the list.
--
-- Test: scripts/stock-loans/tests/loans.sql (on a copy of the enum made in
-- its own rolled-back transaction).

set lock_timeout = '5s';

alter type public.stock_movement_type add value if not exists 'loan_out';
alter type public.stock_movement_type add value if not exists 'loan_return';

do $mig$
declare v text[];
begin
  -- Read from the catalogue: the new values cannot be cast to before commit.
  select array_agg(e.enumlabel::text order by e.enumsortorder) into v
    from pg_enum e where e.enumtypid = 'public.stock_movement_type'::regtype;
  if not ('loan_out' = any (v)) or not ('loan_return' = any (v)) then
    raise exception '400: stock_movement_type has no loan_out or loan_return value (it has %)', v; end if;
  raise notice '400: stock_movement_type is %', v;
end $mig$;
