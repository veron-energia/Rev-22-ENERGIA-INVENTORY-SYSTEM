// The real Invoices page, with the global stylesheet only (as in the app).
import React from 'react';
import { createRoot } from 'react-dom/client';
import { MemoryRouter } from 'react-router-dom';
import '../../../src/styles/globals.css';
import InvoicesPage from '../../../src/pages/InvoicesPage';

createRoot(document.getElementById('root')!).render(
  <MemoryRouter><div style={{ padding: 12, maxWidth: 1180, margin: '0 auto' }}><InvoicesPage /></div></MemoryRouter>);
