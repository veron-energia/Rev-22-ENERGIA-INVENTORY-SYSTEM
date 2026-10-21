export interface ReviewBoxes { acidity: string | null; goals: string | null; cond: string | null; rec: string | null }

export function savedReview(survey: Record<string, any> | null | undefined): ReviewBoxes;

export function reviewState(
  saved: ReviewBoxes,
  draft: { acidity?: string | null; goals?: string | null; cond?: string | null; rec?: string | null },
): { changed: boolean; blanks: boolean; canSave: boolean };
