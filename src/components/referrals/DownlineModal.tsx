import React, { useEffect, useState } from 'react';
import { supabase } from '../../lib/supabase';
import { Modal } from '../ui';
import { ExcelExportButton } from '../ExcelExport';
import { sgDate } from '../../lib/referral/campaign.mjs';
import { RefreshCw } from 'lucide-react';

/** One row of customer_downline_visits (398). */
export interface DownlineRow {
  customer_id: string; name: string; phone: string | null;
  /** The Singapore date of the referral, else of the customer's creation. */
  joined_on: string | null; joined_from_created: boolean;
  visited: boolean; first_visit_on: string | null;
  parent_id?: string; parent_name?: string;
}
interface Downline { customer_id: string; name: string; tier1: DownlineRow[]; tier2: DownlineRow[]; }

const visitedOf = (rows: DownlineRow[]) => rows.filter(r => r.visited).length;

const Table: React.FC<{ rows: DownlineRow[]; tier2?: boolean }> = ({ rows, tier2 }) => (
  <div className="table-wrap" style={{ border: '1px solid var(--border)', borderRadius: 'var(--radius-sm)', maxHeight: 280, overflowY: 'auto' }}>
    <table style={{ fontSize: 12.5 }}>
      <thead><tr>
        <th>Name</th>{tier2 && <th>Referred by</th>}<th>Phone</th><th>Joined</th><th>Visited</th><th>First visit</th>
      </tr></thead>
      <tbody>
        {rows.length === 0 && <tr><td colSpan={tier2 ? 6 : 5} style={{ textAlign: 'center', color: 'var(--text-muted)', padding: 14 }}>No one yet</td></tr>}
        {rows.map(r => (
          <tr key={r.customer_id}>
            <td><strong>{r.name}</strong></td>
            {tier2 && <td style={{ color: 'var(--text-secondary)' }}>{r.parent_name ?? '—'}</td>}
            <td style={{ fontFamily: 'var(--font-display)' }}>{r.phone ?? '—'}</td>
            <td title={r.joined_from_created ? 'No referral date was recorded for this link; this is when the customer was created.' : 'The referral date'}>
              {sgDate(r.joined_on)}{r.joined_from_created && <span style={{ color: 'var(--text-muted)', fontSize: 11 }}> (created)</span>}
            </td>
            <td>{r.visited ? <span className="badge badge-success">Yes</span> : <span className="badge badge-muted">No</span>}</td>
            <td>{r.visited ? sgDate(r.first_visit_on) : '—'}</td>
          </tr>
        ))}
      </tbody>
    </table>
  </div>
);

/**
 * A referrer's downline with visits (398, the Owner's rule of 6 Oct 2026):
 * Tier 1 (whom they referred) and Tier 2 (whom those referred), with phone,
 * joined, visited and the first visit. Owner/Manager only; the database
 * refuses anyone else. Used on the Customers and Affiliates pages.
 */
const DownlineModal: React.FC<{ customerId: string; name: string; onClose: () => void }> = ({ customerId, name, onClose }) => {
  const [data, setData] = useState<Downline | null>(null);
  const [err, setErr] = useState<string | null>(null);
  useEffect(() => {
    let live = true;
    setData(null); setErr(null);
    supabase.rpc('customer_downline_visits', { p_customer_id: customerId }).then(({ data: d, error }) => {
      if (!live) return;
      if (error) { setErr(error.message); return; }
      setData(d as Downline);
    });
    return () => { live = false; };
  }, [customerId]);

  const all = data ? [...data.tier1.map(r => ({ ...r, tier: 'Tier 1' })), ...data.tier2.map(r => ({ ...r, tier: 'Tier 2' }))] : [];
  return (
    <Modal title={`Downline — ${name}`} maxWidth={760} onClose={onClose}
      footer={<>
        {data && <ExcelExportButton rows={all} filename={`downline-${name.replace(/[^\w-]+/g, '-').toLowerCase()}`} sheetName="Downline"
          columns={[
            { header: 'Tier', value: r => r.tier },
            { header: 'Name', value: r => r.name },
            { header: 'Referred By', value: r => r.parent_name ?? name },
            { header: 'Phone', value: r => r.phone ?? '' },
            { header: 'Joined', value: r => sgDate(r.joined_on) },
            { header: 'Joined Is Created Date', value: r => r.joined_from_created ? 'Yes' : 'No' },
            { header: 'Visited', value: r => r.visited ? 'Yes' : 'No' },
            { header: 'First Visit', value: r => r.visited ? sgDate(r.first_visit_on) : '' },
          ]} />}
        <button className="btn btn-secondary" onClick={onClose}>Close</button>
      </>}>
      {err ? <div className="alert alert-danger" style={{ marginBottom: 0 }}><span>⚠</span><div>{err}</div></div>
      : !data ? <div className="empty-state"><RefreshCw size={22} className="spin" style={{ opacity: 0.4 }} /></div>
      : (
        <div className="form-grid">
          <div style={{ fontSize: 12, color: 'var(--text-muted)' }}>
            Joined is the referral date; links made before referral dates were recorded show the date the customer was created.
            Visited means a health survey through the centre&apos;s own QR link, or a consultant&apos;s survey with answers, a note or a file; an event&apos;s survey counts only from a later day&apos;s note or file.
          </div>
          <div>
            <label>Tier 1 — referred by {data.name} ({data.tier1.length}, {visitedOf(data.tier1)} visited)</label>
            <Table rows={data.tier1} />
          </div>
          <div>
            <label>Tier 2 — referred by their Tier 1 ({data.tier2.length}, {visitedOf(data.tier2)} visited)</label>
            <Table rows={data.tier2} tier2 />
          </div>
        </div>
      )}
    </Modal>
  );
};

export default DownlineModal;
