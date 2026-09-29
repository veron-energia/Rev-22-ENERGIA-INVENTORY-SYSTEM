// Only the global stylesheet is loaded here, as in the real app; the page
// imports its own events.css.
import React from 'react';
import { createRoot } from 'react-dom/client';
import { MemoryRouter } from 'react-router-dom';
import '../../../src/styles/globals.css';
import EventsPage from '../../../src/pages/EventsPage';

createRoot(document.getElementById('root')!).render(
  <MemoryRouter>
    <div style={{ padding: 12, maxWidth: 1180, margin: '0 auto' }}>
      <EventsPage />
    </div>
  </MemoryRouter>
);
