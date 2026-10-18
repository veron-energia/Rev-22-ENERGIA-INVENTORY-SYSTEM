import React from 'react';

/**
 * After a deploy (ADMIN-AUTH-8).
 *
 * Each page is its own file, fetched the first time it is opened. A deploy
 * replaces those files with new ones under new names, so a browser still
 * running the old build asks for a file that is gone. Before this, the cashier
 * saw "Something went wrong" with no menu, and Try again failed the same way;
 * only a manual reload helped.
 *
 * Now the app reloads itself once to pick up the new build. A reload is
 * remembered for a few seconds in this tab, so a file that is still missing
 * after it cannot start a loop: the error is shown instead, with a Reload
 * button.
 */

const KEY = 'energia.staleChunkReloadAt';
const GUARD_MS = 10_000;

/** Is this the error a browser gives for a page file it could not fetch? */
export function isChunkLoadError(error: unknown): boolean {
  const message = String((error as { message?: unknown } | null)?.message ?? error ?? '');
  return /Failed to fetch dynamically imported module|error loading dynamically imported module|Importing a module script failed|Unable to preload CSS|Loading chunk [\w-]+ failed|ChunkLoadError/i
    .test(message);
}

/**
 * Reload once to pick up the new build. Answers false, and does nothing, when
 * this tab reloaded for this reason a moment ago or cannot remember that it did.
 */
export function reloadForNewVersion(win: Window = window, now: number = Date.now()): boolean {
  try {
    const last = Number(win.sessionStorage.getItem(KEY) ?? 0);
    if (last && now - last < GUARD_MS) return false;
    win.sessionStorage.setItem(KEY, String(now));
  } catch {
    return false;   // no storage: a reload could not be guarded, so none is made
  }
  win.location.reload();
  return true;
}

/** Vite reports a page file it could not load with this event. */
export function reloadOnStaleChunks(win: Window = window): void {
  win.addEventListener('vite:preloadError', (event) => {
    if (reloadForNewVersion(win)) event.preventDefault();
  });
}

const never = <T,>() => new Promise<T>(() => undefined);

/**
 * React.lazy for a page: one more try after a failed fetch (a network blip),
 * then a reload for a build that has moved on. Any other error is thrown as
 * it was, for the error boundary to show.
 */
export function lazyPage<T extends React.ComponentType<any>>(load: () => Promise<{ default: T }>) {
  return React.lazy(async () => {
    try {
      // Vite answers undefined when the reload above has already started.
      return (await load()) ?? never<{ default: T }>();
    } catch (error) {
      if (!isChunkLoadError(error)) throw error;
      try {
        return (await load()) ?? never<{ default: T }>();
      } catch (again) {
        if (reloadForNewVersion()) return never<{ default: T }>();
        throw again;
      }
    }
  });
}
