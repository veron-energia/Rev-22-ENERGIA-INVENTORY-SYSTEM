// The real Store and Warehouse stock pages and the customer's loans, with the
// global stylesheet only (as in the app). ?page=store|warehouse|customer.
import React, { useState } from 'react';
import { createRoot } from 'react-dom/client';
import { MemoryRouter } from 'react-router-dom';
import '../../../src/styles/globals.css';
import StoreInventoryPage from '../../../src/pages/StoreInventoryPage';
import WarehouseInventoryPage from '../../../src/pages/WarehouseInventoryPage';
import CustomerLoans from '../../../src/components/stock-loans/CustomerLoans';

type Page = 'store' | 'warehouse' | 'customer';
const Harness = () => {
  const first = new URLSearchParams(location.search).get('page');
  const [page, setPage] = useState<Page>(first === 'warehouse' || first === 'customer' ? first : 'store');
  return (
    <div style={{ padding: 12, maxWidth: 1180, margin: '0 auto' }}>
      <div style={{ display: 'flex', gap: 8, marginBottom: 12, flexWrap: 'wrap' }}>
        {(['store', 'warehouse', 'customer'] as const).map(p => (
          <button key={p} className={`btn ${page === p ? 'btn-primary' : 'btn-secondary'}`} onClick={() => setPage(p)}>
            {p === 'store' ? 'Store stock' : p === 'warehouse' ? 'Warehouse stock' : 'Customer profile (Jane Tan)'}
          </button>
        ))}
      </div>
      {page === 'store' && <StoreInventoryPage />}
      {page === 'warehouse' && <WarehouseInventoryPage />}
      {page === 'customer' && <div className="card" style={{ padding: 16, maxWidth: 460 }}><CustomerLoans customerId="c-jane" /></div>}
    </div>
  );
};

createRoot(document.getElementById('root')!).render(<MemoryRouter><Harness /></MemoryRouter>);
