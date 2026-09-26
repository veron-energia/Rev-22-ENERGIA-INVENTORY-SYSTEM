import React from 'react';
import { createRoot } from 'react-dom/client';
import { MemoryRouter } from 'react-router-dom';
import '../../../src/styles/globals.css';
import AffiliateLayout from '../../../src/components/AffiliateLayout';

// The real shell, with the real stylesheet. Resize the window (or emulate a
// width) and read the badge: it reports which of the two navigations the CSS
// is actually showing at this width. "neither" is the bug we are hunting.
const Probe: React.FC = () => {
  const [w, setW] = React.useState(window.innerWidth);
  const [state, setState] = React.useState('');
  React.useEffect(() => {
    const read = () => {
      setW(window.innerWidth);
      const side = document.querySelector('.portal-sidebar') as HTMLElement | null;
      const head = document.querySelector('.portal-mobile-header') as HTMLElement | null;
      const vis = (el: HTMLElement | null) => {
        if (!el) return 'absent';
        const cs = getComputedStyle(el);
        const r = el.getBoundingClientRect();
        return `${cs.display} ${Math.round(r.width)}x${Math.round(r.height)} @${Math.round(r.left)},${Math.round(r.top)}`;
      };
      setState(`sidebar[${vis(side)}] header[${vis(head)}]`);
    };
    read();
    window.addEventListener('resize', read);
    const t = setInterval(read, 400);
    return () => { window.removeEventListener('resize', read); clearInterval(t); };
  }, []);
  return (
    <div id="probe" data-state={state} data-width={w}
         style={{ position: 'fixed', right: 6, bottom: 6, zIndex: 9999, background: '#111', color: '#0f0',
                  font: '11px/1.4 ui-monospace, monospace', padding: '6px 8px', borderRadius: 6, maxWidth: 520 }}>
      {w}px — {state}
    </div>
  );
};

createRoot(document.getElementById('root')!).render(
  <MemoryRouter initialEntries={['/affiliate/dashboard']}>
    <AffiliateLayout>
      <h1 style={{ fontSize: 22, fontWeight: 700, marginBottom: 4 }}>Dashboard</h1>
      <p style={{ color: 'var(--text-secondary)', fontSize: 13.5 }}>Your Energia affiliate overview</p>
    </AffiliateLayout>
    <Probe />
  </MemoryRouter>
);
