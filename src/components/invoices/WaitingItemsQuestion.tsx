import React, { useEffect, useState } from 'react';
import { supabase } from '../../lib/supabase';
import { type WaitingAnswers, type WaitingItem, waitingItemLabel, waitingItemsFromRows } from '../../lib/special/waitingItems';
import './invoice-controls.css';

/** The invoice's special sales and rentals still waiting for a warehouse
 *  (393). Empty when there are none, or when they cannot be read: without an
 *  answer the database still applies its own rule (cancelled only when the
 *  item's line goes back in full). */
export function useWaitingItems(invoiceId: string, reloadKey?: unknown): WaitingItem[] {
  const [items, setItems] = useState<WaitingItem[]>([]);
  useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
        const cols = 'id,status,warehouse_id,source_store_id,invoice_item_id,special_products(name)';
        const [sales, rentals] = await Promise.all([
          supabase.from('special_sales').select(`${cols},sale_no`).eq('invoice_id', invoiceId),
          supabase.from('rentals').select(`${cols},rental_no`).eq('invoice_id', invoiceId),
        ]);
        if (!cancelled) setItems(waitingItemsFromRows((sales as any)?.data, (rentals as any)?.data));
      } catch {
        if (!cancelled) setItems([]);
      }
    })();
    return () => { cancelled = true; };
  }, [invoiceId, reloadKey]);
  return items;
}

/** "Is the customer still taking this item?", once for each waiting item on a
 *  partial refund (the Owner, 6 Oct 2026). Nothing is chosen for them. */
export function WaitingItemsQuestion({ items, answers, onChange, lineName, disabled = false }: {
  items: WaitingItem[]; answers: WaitingAnswers; onChange: (next: WaitingAnswers) => void;
  /** The invoice line's name, which staff know the item by. */
  lineName?: (invoiceItemId: string) => string | undefined;
  disabled?: boolean;
}) {
  if (!items.length) return null;
  return (
    <fieldset className="invoice-guided-stock invoice-waiting-items">
      <legend>Waiting for a warehouse</legend>
      <p className="muted">Is the customer still taking this item? Yes keeps it waiting to be released.
        No cancels it when the refund is recorded. A refund that returns the whole invoice cancels
        every one of them.</p>
      {items.map(item => {
        const label = waitingItemLabel(item, lineName);
        const choose = (taking: boolean) => onChange({ ...answers, [item.doc_id]: taking });
        return (
          <div key={item.doc_id} className="invoice-guided-stock-row" role="radiogroup"
            aria-label={`Is the customer still taking ${label}?`}>
            <span>{label}</span>
            <div className="invoice-waiting-choice">
              <label><input type="radio" name={`waiting-${item.doc_id}`} disabled={disabled}
                checked={answers[item.doc_id] === true} onChange={() => choose(true)} /> Yes, still taking it</label>
              <label><input type="radio" name={`waiting-${item.doc_id}`} disabled={disabled}
                checked={answers[item.doc_id] === false} onChange={() => choose(false)} /> No, cancel it</label>
            </div>
          </div>
        );
      })}
    </fieldset>
  );
}
