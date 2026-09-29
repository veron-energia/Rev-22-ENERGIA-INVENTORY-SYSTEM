// Only the global stylesheet is loaded here, as in the real app.
import React from 'react';
import { createRoot } from 'react-dom/client';
import { MemoryRouter } from 'react-router-dom';
import '../../../src/styles/globals.css';
import ReportsPage from '../../../src/pages/ReportsPage';

createRoot(document.getElementById('root')!).render(
  <MemoryRouter>
    <div style={{ padding: 12, maxWidth: 1180, margin: '0 auto' }}>
      <ReportsPage />
    </div>
  </MemoryRouter>
);
