import React from 'react';
import { createRoot } from 'react-dom/client';
import '../../../src/styles/globals.css';
import SurveysPage from '../../../src/pages/SurveysPage';

createRoot(document.getElementById('root')!).render(
  <div style={{ padding: 20, maxWidth: 1180, margin: '0 auto' }}><SurveysPage /></div>,
);
