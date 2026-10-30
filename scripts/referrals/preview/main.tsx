import React from 'react';
import { createRoot } from 'react-dom/client';
import { MemoryRouter } from 'react-router-dom';
import '../../../src/styles/globals.css';
import CustomersPage from '../../../src/pages/CustomersPage';
import AffiliatesPage from '../../../src/pages/AffiliatesPage';
import AffiliateNetworkPage from '../../../src/pages/AffiliateNetworkPage';
import DownlineModal from '../../../src/components/referrals/DownlineModal';

// The real pages, with the real stylesheet, against supabase-stub.ts.
// ?view=customers | affiliates | promotion | network | downline, ?role=owner |
// manager | staff, ?status=provisional | final; 480: ?bookings=old answers as a
// database before 480 (no booking keys).
const params = new URLSearchParams(window.location.search);
const view = params.get('view') ?? 'customers';

const Promotion: React.FC = () => {
  // Opens the Affiliates page on its Referral promotion tab.
  React.useEffect(() => {
    const t = setInterval(() => {
      const b = [...document.querySelectorAll('button')].find(x => x.textContent?.trim() === 'Referral promotion');
      if (b) { (b as HTMLButtonElement).click(); clearInterval(t); }
    }, 100);
    return () => clearInterval(t);
  }, []);
  return <AffiliatesPage />;
};

// 480: the Downline window on its own (Fay Lum's), with its Booking column.
const Downline: React.FC = () => <DownlineModal customerId="c-fay" name="Fay Lum" onClose={() => {}} />;

const Page = view === 'network' ? AffiliateNetworkPage
  : view === 'downline' ? Downline
  : view === 'affiliates' ? AffiliatesPage
  : view === 'promotion' ? Promotion : CustomersPage;

createRoot(document.getElementById('root')!).render(
  <MemoryRouter>
    {view === 'network' ? <Page /> : <div className="main-content" style={{ padding: 24 }}><Page /></div>}
  </MemoryRouter>,
);
