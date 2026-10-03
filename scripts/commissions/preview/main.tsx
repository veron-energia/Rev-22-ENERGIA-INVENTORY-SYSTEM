import { createRoot } from 'react-dom/client';
import { MemoryRouter } from 'react-router-dom';
import '../../../src/styles/globals.css';
import ReportsPage from '../../../src/pages/ReportsPage';

// The real Reports page and stylesheet against fixture data (supabase-stub.ts).
// #reports-error and #reports-stale switch the staff report's fixture.
createRoot(document.getElementById('root')!).render(
  <MemoryRouter><div style={{ padding: 24 }}><ReportsPage /></div></MemoryRouter>
);
