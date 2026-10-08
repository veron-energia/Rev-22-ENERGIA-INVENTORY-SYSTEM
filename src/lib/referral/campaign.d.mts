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
  /** 404: friends referred in the window who have not visited yet. */
  counted?: number; not_yet_visited?: number; referred_in_window?: number;
  tier_reached?: number | null; next_tier?: number | null; to_next?: number | null;
  reward_tier?: number | null; reward_given_at?: string | null;
}
export function progressLine(p: PortalProgress | null | undefined): string;
/** 404: "{n} friends you referred during the promotion haven't visited yet."; '' at 0, without the figure, or after the end. */
export function portalNotYetVisitedLine(p: PortalProgress | null | undefined): string;
/** A friend as referral_campaign_report lists them. */
export interface PromotionFriend { counted: boolean; first_visit_on: string | null; }
/** not_yet_visited when the report sends it (404), else the friends listed without a visit. */
export function notYetVisited(row: { not_yet_visited?: number | null; friends?: readonly PromotionFriend[] | null } | null | undefined): number;
/** The line under a referrer's name; '' when none of their friends is waiting for a first visit. */
export function notYetVisitedLine(n: number | string | null | undefined, status: CampaignInfo['status'] | null | undefined): string;
export function friendStatus(friend: PromotionFriend | null | undefined, status: CampaignInfo['status'] | null | undefined): string;
/** The referrer table's line when it shows nobody: listed is how many referrers the report gives, onlyCounted the filter. */
export function emptyReportNote(listed: number, onlyCounted: boolean): string;
export interface RewardLine { product_id: string; quantity: string | number; }
export function rewardItems(lines: readonly RewardLine[] | null | undefined):
  { items: { product_id: string; quantity: number }[]; error: null } | { items: null; error: string };
