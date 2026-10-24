/** A part of a copy: its rows' heights (one number: one row). */
export interface CopyUnit {
  /** 'head': page 1's header down to the items; 'line': an item line; 'tail': the totals down to the footer. */
  kind: 'head' | 'line' | 'tail';
  rows: readonly number[] | number;
  /** The table (or note) its rows are in, by index into theads. */
  table?: number;
}
/** The heights planCopyPages plans from (any one unit). */
export interface CopyPageHeights {
  /** What one page of the copy holds. */
  cap: number;
  /** Pages 2 onward: the compact "(continued)" line. */
  contHead: number;
  /** The "Continued on page k+1" line ending every page but the last. */
  foot: number;
  /** The copy's parts, top to bottom. */
  units?: readonly CopyUnit[];
  /** What each table takes on every page its rows are on (its head row and margins). */
  theads?: readonly number[];
  /** The plain shape, in place of units and theads: the head (or its parts), ... */
  head?: number | readonly (readonly number[] | number)[];
  /** ... the item table's head row, ... */
  thead?: number;
  /** ... each item line as its rows' heights: the line, then its promotion sub-rows, ... */
  groups?: readonly (readonly number[] | number)[];
  /** ... and the tail's parts in order (each a height, or its rows' heights), or its height alone. */
  tail?: readonly (readonly number[] | number)[] | number;
}
/** One page: rows [from, to) of all the units' rows, in order. */
export interface CopyPage { from: number; to: number; first: boolean; last: boolean }
export function planCopyPages(p: CopyPageHeights): CopyPage[];
/** Lays the print window's sheet out as the pages its copies need; returns how many sheets. */
export function paginatePrintCopies(plan: typeof planCopyPages): number;
/** Defines planCopyPages and paginatePrintCopies for the print window. */
export const PRINT_PAGES_SCRIPT: string;
