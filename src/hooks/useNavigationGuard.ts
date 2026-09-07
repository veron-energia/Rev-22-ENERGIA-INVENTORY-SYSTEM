import { useCallback, useEffect, useRef } from 'react';

/**
 * Warn a customer before they leave an unfinished survey.
 *
 * The app mounts a plain `<BrowserRouter>` (not a data router), so
 * `useBlocker` is unavailable. The public survey is a standalone route with no
 * in‑app navigation links, so two mechanisms cover every realistic exit:
 *
 *  - `beforeunload` — refresh, tab / window close, and cross‑document
 *    navigation. The browser shows its own generic prompt; the wording and
 *    buttons cannot be customised, and some mobile browsers ignore it entirely.
 *  - `popstate` — the browser Back / Forward buttons. A single sentinel history
 *    entry is pushed the first time the form becomes guarded; when the customer
 *    tries to pop past it we re‑push it and raise the in‑app dialog instead.
 *
 * Guarantees:
 *  - nothing is pushed while `when` is false (an untouched form adds no history);
 *  - at most one sentinel entry exists at a time (no history loops / stacking);
 *  - `confirmLeave()` performs the real navigation the customer asked for;
 *  - all listeners are removed on unmount and when `when` becomes false.
 */
export function useNavigationGuard(opts: {
  /** true when there are meaningful unsaved changes OR a submission is in flight */
  when: boolean;
  /** raise the in‑app confirmation dialog */
  onBlockedPop: () => void;
}) {
  const { when, onBlockedPop } = opts;

  const whenRef = useRef(when);
  whenRef.current = when;
  const onBlockedRef = useRef(onBlockedPop);
  onBlockedRef.current = onBlockedPop;

  const armedRef = useRef(false);
  const bypassRef = useRef(false);

  const hasSentinel = () =>
    typeof window !== 'undefined' &&
    !!(window.history.state && (window.history.state as Record<string, unknown>).__surveyGuard);

  const pushSentinel = () => {
    window.history.pushState(
      { ...(window.history.state as object | null), __surveyGuard: true },
      '',
    );
  };

  // beforeunload — only attached while guarded.
  useEffect(() => {
    if (!when) return;
    const handler = (e: BeforeUnloadEvent) => {
      e.preventDefault();
      // Legacy browsers need a string assignment; modern ones ignore it.
      e.returnValue = '';
    };
    window.addEventListener('beforeunload', handler);
    return () => window.removeEventListener('beforeunload', handler);
  }, [when]);

  // popstate — mounted once for the life of the hook.
  useEffect(() => {
    const onPop = () => {
      if (bypassRef.current) {
        bypassRef.current = false;
        return;
      }
      if (whenRef.current) {
        // Stay put and ask. Re‑push so a subsequent Back is caught again.
        pushSentinel();
        onBlockedRef.current();
      } else {
        // Clean form (or already submitted): let the navigation stand.
        armedRef.current = false;
      }
    };
    window.addEventListener('popstate', onPop);
    return () => window.removeEventListener('popstate', onPop);
  }, []);

  // Arm the sentinel the first time the form becomes guarded.
  useEffect(() => {
    if (when && !armedRef.current) {
      if (!hasSentinel()) pushSentinel();
      armedRef.current = true;
    }
  }, [when]);

  /** Proceed with the navigation the customer confirmed. */
  const confirmLeave = useCallback(() => {
    bypassRef.current = true;
    armedRef.current = false;
    // We are sitting on the re‑pushed sentinel; step back past it and the form.
    if (window.history.length > 2) window.history.go(-2);
    else window.history.back();
  }, []);

  return { confirmLeave };
}
