// Print from the app, not from the print window. The window the app opens with
// window.open('', '_blank') and fills with document.write inherits the app's
// Content-Security-Policy (script-src 'self', no 'unsafe-inline'), so an inline
// <script> written into it would be blocked. The print window therefore holds
// no script: once its document is ready the app runs the layout steps on it,
// then prints it.

/** A layout step: run on the print window's document, from the opener. */
export type PrintStep = (doc: Document) => unknown;

/** How long to wait for the print window's load (logos, fonts) before laying out anyway. */
export const PRINT_READY_FALLBACK_MS = 3000;

/**
 * Once the print window's images have settled, runs each step on `w.document` in
 * order, each in its own try/catch (a failed step leaves the sheet as it was and
 * the print goes ahead), then focuses and prints. Does nothing if the window was
 * closed meanwhile. Never throws.
 *
 * Why images, not readyState: Chrome reports readyState 'complete' right after
 * document.write + close() while the logos are still loading, so laying out and
 * printing then would measure and print the sheet without them. The old inline
 * script waited for window.onload, which waits for the images; this waits for
 * every image not yet complete to load or fail (a failed one counts as settled),
 * with a fallback timer so it never waits forever.
 */
export function printWhenReady(w: Window, steps: PrintStep[], fallbackMs: number = PRINT_READY_FALLBACK_MS): void {
  let done = false;
  let timer: ReturnType<typeof setTimeout> | undefined;
  const run = () => {
    if (done) return;
    done = true;
    if (timer !== undefined) clearTimeout(timer);
    try {
      if (w.closed) return;
      const doc = w.document;
      for (const step of steps) {
        try { step(doc); } catch { /* a failed step prints the sheet as it is */ }
      }
      try { w.focus(); } catch { /* not every window can take focus */ }
      w.print();
    } catch { /* the window went away: nothing to print */ }
  };
  const pending = () => Array.from(w.document.images ?? []).filter(i => !i.complete);
  try {
    if (w.closed) return;
    const waiting = pending();
    if (!waiting.length) { run(); return; }
    let left = waiting.length;
    const settled = () => { if (--left <= 0) run(); };
    for (const img of waiting) {
      let once = false;
      const one = () => { if (!once) { once = true; settled(); } };
      try {
        img.addEventListener('load', one, { once: true });
        img.addEventListener('error', one, { once: true });
      } catch { /* the timer covers it */ }
    }
    // An image may have completed between the filter and the listeners.
    if (pending().length === 0) { run(); return; }
  } catch { /* the timer covers it */ }
  timer = setTimeout(run, fallbackMs);
}
