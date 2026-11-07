import { useRef } from 'react';

/** Asks before a form's work is thrown away, only when there is work to lose. */
export const okToDiscard = (changed: boolean) =>
  !changed || window.confirm('Discard what you have entered? It will not be saved.');

/**
 * Whether a form's values differ from what they were when it opened, so closing
 * it asks first only once something would be lost.
 *
 * Keep `open` false until a form that fills itself in after opening has finished
 * doing so, or that filling would count as a change.
 */
export function useChangedSinceOpened(open: boolean, values: unknown): boolean {
  const opened = useRef<string | null>(null);
  if (!open) { opened.current = null; return false; }
  const now = JSON.stringify(values);
  if (opened.current === null) opened.current = now;
  return now !== opened.current;
}
