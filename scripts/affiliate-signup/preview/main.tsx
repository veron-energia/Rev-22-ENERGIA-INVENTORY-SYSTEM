import React from 'react';
import { createRoot } from 'react-dom/client';
import { MemoryRouter, Routes, Route } from 'react-router-dom';
import '../../../src/styles/globals.css';
import ReferralSignupPage from '../../../src/pages/ReferralSignupPage';
import { rpcCalls } from './supabase-stub';

// The page leaves for cal.com with window.location.href. Hold it here and show
// where it was going, so the booking address can be read without leaving.
const nav = (window as any).navigation;
nav?.addEventListener('navigate', (e: any) => {
  const to = e.destination?.url ?? '';
  if (!to.startsWith(window.location.origin) && e.cancelable) {
    e.preventDefault();
    const out = document.getElementById('leaving')!;
    out.dataset.url = to;
    out.dataset.calls = JSON.stringify(rpcCalls);
    out.textContent = `Would open: ${decodeURIComponent(to)}`;
    out.style.display = 'block';
  }
});

createRoot(document.getElementById('root')!).render(
  <>
    <div id="leaving" style={{ display: 'none', position: 'fixed', left: 6, right: 6, bottom: 6, zIndex: 9999,
      background: '#111', color: '#0f0', font: '12px/1.4 ui-monospace, monospace', padding: '8px 10px',
      borderRadius: 6, wordBreak: 'break-all' }} />
    <MemoryRouter initialEntries={['/r/ENPREVIEW']}>
      <Routes><Route path="/r/:referralCode" element={<ReferralSignupPage />} /></Routes>
    </MemoryRouter>
  </>
);
