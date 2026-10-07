import React from 'react';
import { createRoot } from 'react-dom/client';
import { MemoryRouter } from 'react-router-dom';
import '../../../src/styles/globals.css';
import CustomersPage from '../../../src/pages/CustomersPage';
import AffiliatesPage from '../../../src/pages/AffiliatesPage';
import AffiliateNetworkPage from '../../../src/pages/AffiliateNetworkPage';

// The real pages, with the real stylesheet, against supabase-stub.ts.
// ?view=customers | affiliates | promotion | network, ?role=owner | manager |
// staff, ?status=provisional | final.
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

const Page = view === 'network' ? AffiliateNetworkPage
  : view === 'affiliates' ? AffiliatesPage
  : view === 'promotion' ? Promotion : CustomersPage;

createRoot(document.getElementById('root')!).render(
  <MemoryRouter>
    {view === 'network' ? <Page /> : <div className="main-content" style={{ padding: 24 }}><Page /></div>}
  </MemoryRouter>,
);
