import { createRoot } from 'react-dom/client';
import { MemoryRouter } from 'react-router-dom';
import '../../../src/styles/globals.css';
import StaffCommissionsPage from '../../../src/pages/StaffCommissionsPage';
import ReportsPage from '../../../src/pages/ReportsPage';

// The real pages and stylesheet against fixture data (supabase-stub.ts).
// #reports (and #reports-error, #reports-stale) shows the Reports page; anything else, Staff Commissions.
const Page = window.location.hash.startsWith('#reports') ? ReportsPage : StaffCommissionsPage;
createRoot(document.getElementById('root')!).render(
  <MemoryRouter><div style={{ padding: 24 }}><Page /></div></MemoryRouter>
);
