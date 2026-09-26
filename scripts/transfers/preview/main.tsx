// Only the global stylesheet is loaded here, as in the real app: whatever else
// a page needs it must import itself. That is what left the invoice review
// popup unstyled when it was opened from Approvals.
import React, { useState } from 'react';
import { createRoot } from 'react-dom/client';
import { MemoryRouter } from 'react-router-dom';
import '../../../src/styles/globals.css';
import ApprovalsPage from '../../../src/pages/ApprovalsPage';
import TransfersPage from '../../../src/pages/TransfersPage';

const Harness = () => {
  const [page, setPage] = useState<'approvals' | 'transfers'>(
    new URLSearchParams(location.search).get('page') === 'transfers' ? 'transfers' : 'approvals');
  return (
    <div style={{ padding: 12, maxWidth: 1180, margin: '0 auto' }}>
      <div style={{ display: 'flex', gap: 8, marginBottom: 12 }}>
        <button className={`btn ${page === 'approvals' ? 'btn-primary' : 'btn-secondary'}`} onClick={() => setPage('approvals')}>Approvals</button>
        <button className={`btn ${page === 'transfers' ? 'btn-primary' : 'btn-secondary'}`} onClick={() => setPage('transfers')}>Transfers</button>
      </div>
      {page === 'approvals' ? <ApprovalsPage /> : <TransfersPage />}
    </div>
  );
};

createRoot(document.getElementById('root')!).render(<MemoryRouter><Harness /></MemoryRouter>);
