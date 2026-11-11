import React from 'react';
import { createRoot } from 'react-dom/client';
import '../../../src/styles/globals.css';
import { CustomerTherapySummary } from '../../../src/components/therapy/CustomerTherapySummary';
import { HolidayAdmin } from '../../../src/components/therapy/HolidayAdmin';
import { RecalculationPreview } from '../../../src/components/therapy/TherapyDiagnostics';

const Section: React.FC<{ title: string; children: React.ReactNode }> = ({ title, children }) => (
  <section className="card" style={{ padding: 14, marginBottom: 16 }}>
    <h3 style={{ fontSize: 14.5, marginBottom: 10 }}>{title}</h3>
    {children}
  </section>
);

// The parts of Therapy → Purchased and Therapy → Holidays that stand alone.
// (502: the reward choice and the reward mapping preview are gone with the old
// same-day spending reward.)
createRoot(document.getElementById('root')!).render(
  <div style={{ padding: 12, maxWidth: 1180, margin: '0 auto' }}>
    <Section title="Customer therapy holdings"><CustomerTherapySummary /></Section>
    <Section title="Holiday calendars"><HolidayAdmin canManage /></Section>
    <Section title="Recalculation preview"><RecalculationPreview canManage /></Section>
  </div>
);
