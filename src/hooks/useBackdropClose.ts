import { useRef, type MouseEvent } from 'react';

/**
 * Props for the backdrop behind a popup: a click on the backdrop closes the
 * popup, and a drag that only starts or ends there does not.
 *
 * A browser sends the click of a press and a release on different elements to
 * the nearest element holding both. So selecting text in a field and letting go
 * outside the popup reaches the backdrop as a click on the backdrop itself, and
 * the click alone cannot be told apart from a real one; the press and the release
 * can. They are read on the way down (capture), so nothing in the popup can stop
 * them first.
 */
export function useBackdropClose(close: () => void) {
  const touchedPopup = useRef(false);
  const inPopup = (e: MouseEvent) => e.target !== e.currentTarget;
  return {
    onMouseDownCapture: (e: MouseEvent) => { touchedPopup.current = inPopup(e); },
    onMouseUpCapture: (e: MouseEvent) => { if (inPopup(e)) touchedPopup.current = true; },
    onClick: (e: MouseEvent) => {
      const dragged = touchedPopup.current;
      touchedPopup.current = false;
      if (!dragged && !inPopup(e)) close();
    },
  };
}
