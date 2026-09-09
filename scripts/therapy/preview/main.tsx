import React from 'react';
import { createRoot } from 'react-dom/client';
import '../../../src/styles/globals.css';
import { CustomerTherapySummary } from '../../../src/components/therapy/CustomerTherapySummary';
import { RewardChoice } from '../../../src/components/therapy/RewardChoice';
import { HolidayAdmin } from '../../../src/components/therapy/HolidayAdmin';
import { RecalculationPreview, RewardMappingPreview } from '../../../src/components/therapy/TherapyDiagnostics';

const Section: React.FC<{ title: string; children: React.ReactNode }> = ({ title, children }) => (
  <section className="card" style={{ padding: 14, marginBottom: 16 }}>
    <h3 style={{ fontSize: 14.5, marginBottom: 10 }}>{title}</h3>
    {children}
  </section>
);

createRoot(document.getElementById('root')!).render(
  <div style={{ padding: 12, maxWidth: 1180, margin: '0 auto' }}>
    <Section title="Customer therapy holdings"><CustomerTherapySummary /></Section>
    <Section title="Reward choice">
      <RewardChoice canManage entitlement={{ id: 'e1', store_id: 's1', entitlement_no: 'ENT-1' }}
                    claimDate="2026-09-10" holidayCountry="SG" holidayRegion={null}
                    onClaimed={() => {}} />
    </Section>
    <Section title="Unclaimed entitlements"><RewardMappingPreview canManage /></Section>
    <Section title="Holiday calendars"><HolidayAdmin canManage /></Section>
    <Section title="Recalculation preview"><RecalculationPreview canManage /></Section>
  </div>
);
