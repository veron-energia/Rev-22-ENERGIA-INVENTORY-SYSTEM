export type VisitedFilter = '' | 'visited' | 'not_visited';
/** Only the filters in use; none at all when no filter is on. */
export interface VisitFilterArgs {
  p_visited?: 'visited' | 'not_visited';
  p_visit_from?: string;
  p_visit_to?: string;
}
export function visitFilterArgs(visited: string | null | undefined, from: string | null | undefined,
  to: string | null | undefined): VisitFilterArgs;
export function visitFilterActive(visited: string | null | undefined, from: string | null | undefined,
  to: string | null | undefined): boolean;
export function sgDate(d: string | null | undefined): string;
/** The Singapore day of a timestamp (e.g. a reward's given_at), dd/mm/yyyy. */
export function sgDayOf(ts: string | null | undefined): string;
export interface TierStanding { tierReached: number | null; nextTier: number | null; toNext: number | null; }
export function tierStanding(count: number | string | null | undefined, tiers: readonly (number | string)[] | null | undefined): TierStanding;
export function windowLabel(startsOn: string | null | undefined, endsOn: string | null | undefined): string;
export interface CampaignInfo {
  code: string; title: string; starts_on: string; ends_on: string; tiers: number[];
  status: 'provisional' | 'final' | 'not_started'; today?: string; reward_reason?: string;
}
export function statusNote(campaign: CampaignInfo | null | undefined): string;
/** affiliate_portal_campaign_progress() */
export interface PortalProgress {
  campaign: Pick<CampaignInfo, 'code' | 'title' | 'starts_on' | 'ends_on' | 'tiers' | 'status'> | null;
  counted?: number; referred_in_window?: number;
  tier_reached?: number | null; next_tier?: number | null; to_next?: number | null;
  reward_tier?: number | null; reward_given_at?: string | null;
}
export function progressLine(p: PortalProgress | null | undefined): string;
export interface RewardLine { product_id: string; quantity: string | number; }
export function rewardItems(lines: readonly RewardLine[] | null | undefined):
  { items: { product_id: string; quantity: number }[]; error: null } | { items: null; error: string };
