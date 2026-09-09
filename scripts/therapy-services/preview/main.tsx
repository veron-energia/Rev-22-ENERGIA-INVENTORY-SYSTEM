import React from 'react';
import { createRoot } from 'react-dom/client';
import { MemoryRouter } from 'react-router-dom';
import '../../../src/styles/globals.css';
import TherapyServicesPage from '../../../src/pages/TherapyServicesPage';

createRoot(document.getElementById('root')!).render(
  <MemoryRouter>
    <div style={{ padding: 12, maxWidth: 1180, margin: '0 auto' }}>
      <TherapyServicesPage />
    </div>
  </MemoryRouter>
);
