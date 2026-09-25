// The whole Therapy page against the stub: packages covering services and the
// one-step Claim (359). Nothing here talks to a database.
import React from 'react';
import { createRoot } from 'react-dom/client';
import '../../../src/styles/globals.css';
import TherapyPage from '../../../src/pages/TherapyPage';

createRoot(document.getElementById('root')!).render(
  <div style={{ padding: 12, maxWidth: 1280, margin: '0 auto' }}><TherapyPage /></div>
);
