import React from 'react';
import { describeFrequency, FrequencyKind } from '../../lib/therapy/frequency.mjs';

/**
 * What a package's unlimited therapy covers.
 *
 * A package linked to services A and B lets the customer take A or B as often
 * as they like while it runs. Each service's own limit still applies, so it is
 * shown next to the service — nothing records a visit yet, which makes the
 * wording the only place staff learn it.
 */
export type Covered = { service_id?: string; name: string; limit?: string | null; archived?: boolean };

type ServiceRow = {
  id: string; name: string;
  frequency_kind?: FrequencyKind | null;
  frequency_max_per_period?: number | null;
  frequency_interval_hours?: number | null;
  deleted_at?: string | null;
};

/** A therapy_services row's limit, worded as the database words it; null when it has none. */
export const serviceLimit = (sv: ServiceRow): string | null =>
  !sv.frequency_kind || sv.frequency_kind === 'unrestricted' ? null
    : describeFrequency({
        kind: sv.frequency_kind,
        max_per_period: sv.frequency_max_per_period ?? 1,
        interval_hours: sv.frequency_interval_hours ?? undefined,
      });

/** "At most once every 5 hours, measured from …" → "once every 5 hours". */
export const shortLimit = (limit?: string | null): string | null => {
  if (!limit) return null;
  return limit.replace(/^At most\s+/i, '').replace(/\s*[,(].*$/, '').replace(/\.\s*$/, '').trim() || null;
};

/** Service ids, resolved against the loaded catalogue (archived services included). */
export const coveredFrom = (ids: string[] | null | undefined, services: ServiceRow[]): Covered[] =>
  (ids ?? [])
    .map(id => services.find(s => s.id === id))
    .filter((s): s is ServiceRow => !!s)
    .map(s => ({ service_id: s.id, name: s.name, limit: serviceLimit(s), archived: !!s.deleted_at }))
    .sort((a, b) => a.name.localeCompare(b.name));

export const coverageText = (services: Covered[]): string =>
  services.map(s => {
    const lim = shortLimit(s.limit);
    return lim ? `${s.name} (${lim})` : s.name;
  }).join(', ');

/** "Covers A, B (once every 5 hours)", or nothing when no services are linked. */
export const CoverageLine: React.FC<{ services: Covered[]; lead?: string; style?: React.CSSProperties }> =
  ({ services, lead = 'Covers', style }) => {
    if (!services.length) return null;
    return (
      <div className="therapy-coverage" style={{ fontSize: 11, color: 'var(--text-muted)', ...style }}>
        {lead} {coverageText(services)}
      </div>
    );
  };
