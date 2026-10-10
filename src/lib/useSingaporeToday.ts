import { useEffect, useState } from 'react';
import { singaporeToday } from './invoices/business';

/** How often the date is read again while the page stays open. */
export const SINGAPORE_TODAY_REFRESH_MS = 60_000;

/**
 * Today's date in Singapore ("2026-10-20"), kept current.
 *
 * A page left open overnight must not keep yesterday's date: a door device
 * left on the Events page since day 1 would check people in for day 1 during
 * day 2. So the date is read again every minute, when the window gets focus
 * back, and when the tab is shown again. It changes only when the day does.
 */
export function useSingaporeToday(): string {
  const [today, setToday] = useState(() => singaporeToday());

  useEffect(() => {
    const read = () => setToday(prev => {
      const now = singaporeToday();
      return now && now !== prev ? now : prev;
    });
    const onVisible = () => { if (document.visibilityState === 'visible') read(); };
    const timer = window.setInterval(read, SINGAPORE_TODAY_REFRESH_MS);
    window.addEventListener('focus', read);
    document.addEventListener('visibilitychange', onVisible);
    read();
    return () => {
      window.clearInterval(timer);
      window.removeEventListener('focus', read);
      document.removeEventListener('visibilitychange', onVisible);
    };
  }, []);

  return today;
}

export default useSingaporeToday;
