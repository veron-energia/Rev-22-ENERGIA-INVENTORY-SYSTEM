import { createRoot } from 'react-dom/client';
import { MemoryRouter } from 'react-router-dom';
import '../../../src/styles/globals.css';
import CommissionsPage from '../../../src/pages/CommissionsPage';

// The real Commissions page and stylesheet against fixture data
// (supabase-stub.ts), inside the app's content area. #commissions-empty sends
// no balances.
createRoot(document.getElementById('root')!).render(
  <MemoryRouter><div className="app-main" style={{ maxWidth: 1200, margin: '0 auto' }}><CommissionsPage /></div></MemoryRouter>
);
