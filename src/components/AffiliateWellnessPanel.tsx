import React, { useEffect, useRef, useState } from 'react';
import { Pause, Play } from 'lucide-react';
import { AnalysisScene, ConnectedPeople, FootSpaScene, RechargeScene } from './AffiliateWellnessScenes';
import './affiliate-wellness.css';

// The brand panel of the affiliate Sign in and Join pages (6 Nov 2026), rendered
// after the form in the page, so the form comes first for the keyboard, for a
// screen reader and on a phone. On a wide screen the stylesheet moves it to the
// left. Nothing in it touches the form.
export type WellnessVariant = 'join' | 'login';

const COPY: Record<WellnessVariant, { lead: string; accent: string; support: string }> = {
  join: { lead: 'Share wellness. ', accent: 'Grow together.', support: 'Become part of the Energia affiliate community.' },
  login: { lead: 'Welcome back to ', accent: 'Energia.', support: 'Sign in to your affiliate portal.' },
};

// Going between Sign in and Join mounts the panel again; someone who paused the
// animation should not have to pause it again.
const PAUSED_KEY = 'energia_aff_wellness_paused';
function readPaused() {
  try { return localStorage.getItem(PAUSED_KEY) === '1'; } catch { return false; }
}

const AffiliateWellnessPanel: React.FC<{ variant: WellnessVariant }> = ({ variant }) => {
  const headingId = React.useId();
  const panel = useRef<HTMLElement>(null);
  const [paused, setPaused] = useState(readPaused);
  const quiet = variant === 'login';
  const { lead, accent, support } = COPY[variant];

  // No painting while it cannot be seen: on a phone it starts below the form.
  useEffect(() => {
    const el = panel.current;
    if (!el || typeof IntersectionObserver === 'undefined') return;
    const watcher = new IntersectionObserver(([entry]) => el.toggleAttribute('data-offscreen', !entry.isIntersecting));
    watcher.observe(el);
    return () => watcher.disconnect();
  }, []);

  const toggle = () => {
    const next = !paused;
    setPaused(next);
    try { localStorage.setItem(PAUSED_KEY, next ? '1' : '0'); } catch { /* the choice lasts this visit */ }
  };

  return (
    <aside ref={panel} className={`aff-wellness aff-wellness--${variant}`} aria-labelledby={headingId} data-paused={paused ? '' : undefined}>
      <h2 id={headingId} className="aff-wellness-headline">{lead}<span className="aff-wellness-accent">{accent}</span></h2>
      <p className="aff-wellness-support">{support}</p>
      <div className="aff-wellness-art">
        <div className="aff-wellness-tile aff-wellness-tile--recharge">
          <div className="aff-wellness-stage"><RechargeScene quiet={quiet} /></div>
          {!quiet && <p className="aff-wellness-caption">Power Recharge Therapy</p>}
        </div>
        <div className="aff-wellness-tile">
          <div className="aff-wellness-stage"><FootSpaScene quiet={quiet} /></div>
          {!quiet && <p className="aff-wellness-caption">Power Foot Detox Therapy</p>}
        </div>
        <div className="aff-wellness-tile">
          <div className="aff-wellness-stage"><AnalysisScene quiet={quiet} /></div>
          {!quiet && <p className="aff-wellness-caption">AcuGraph Energy Analysis</p>}
        </div>
      </div>
      <div className="aff-wellness-foot">
        {!quiet && <ConnectedPeople />}
        <button type="button" className="aff-wellness-toggle" onClick={toggle}>
          {paused ? <Play size={14} aria-hidden="true" /> : <Pause size={14} aria-hidden="true" />}
          {paused ? 'Resume animation' : 'Pause animation'}
        </button>
      </div>
    </aside>
  );
};

export default AffiliateWellnessPanel;
