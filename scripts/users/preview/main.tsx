import React from 'react';
import { createRoot } from 'react-dom/client';
import { MemoryRouter } from 'react-router-dom';
import '../../../src/styles/globals.css';
import { InviteUserForm } from '../../../src/components/users/InviteUserForm';
import AcceptInvitationPage from '../../../src/pages/AcceptInvitationPage';

createRoot(document.getElementById('root')!).render(
  <MemoryRouter>
    <div style={{ padding: 12, maxWidth: 1180, margin: '0 auto' }}>
      <section className="card" style={{ padding: 14, marginBottom: 16 }}>
        <h3 style={{ fontSize: 14.5, marginBottom: 10 }}>Invite a user</h3>
        <InviteUserForm onInvited={() => {}} onClose={() => {}} />
      </section>
      <section className="card" style={{ padding: 0, marginBottom: 16, overflow: 'hidden' }}>
        <AcceptInvitationPage />
      </section>
    </div>
  </MemoryRouter>
);
