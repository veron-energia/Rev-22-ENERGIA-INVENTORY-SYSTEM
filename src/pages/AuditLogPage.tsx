import React, { useEffect, useState, useCallback } from 'react';
import { supabase } from '../lib/supabase';
import { useAuth } from '../context/AuthContext';
import { AuditLog, Profile, isManagerOrAbove } from '../types';
import { NoAccess } from '../components/ui';
import { RefreshCw, ScrollText, Search } from 'lucide-react';

const ACTION_CLS: Record<string, string> = {
  stock_in: 'badge-success', invoice_paid: 'badge-success', restored: 'badge-success',
  transfer_approved: 'badge-success', adjustment_approved: 'badge-success',
  invoice_refunded: 'badge-danger', invoice_cancelled: 'badge-danger',
  transfer_rejected: 'badge-danger', invoice_deleted: 'badge-danger',
  transfer_partially_approved: 'badge-primary',
};

const AuditLogPage: React.FC = () => {
  const { profile } = useAuth();
  if (!isManagerOrAbove(profile?.role)) return <NoAccess message="Only Owners, Admins, and Managers can view the audit log." />;

  const [logs, setLogs] = useState<AuditLog[]>([]);
  const [profiles, setProfiles] = useState<Profile[]>([]);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState('');
  const [tableFilter, setTableFilter] = useState('all');

  const load = useCallback(async () => {
    setLoading(true);
    const [lg, prof] = await Promise.all([
      supabase.from('audit_logs').select('*').order('created_at', { ascending: false }).limit(500),
      supabase.from('profiles').select('id,full_name'),
    ]);
    setLogs((lg.data as AuditLog[]) ?? []);
    setProfiles((prof.data as Profile[]) ?? []);
    setLoading(false);
  }, []);
  useEffect(() => { load(); }, [load]);

  const uName = (id: string | null) => id ? (profiles.find(p => p.id === id)?.full_name ?? '—') : 'System';
  const tables = ['all', ...Array.from(new Set(logs.map(l => l.table_name)))];

  const filtered = logs.filter(l => {
    if (tableFilter !== 'all' && l.table_name !== tableFilter) return false;
    const q = search.toLowerCase();
    return !q || l.action.toLowerCase().includes(q) || l.table_name.toLowerCase().includes(q) || uName(l.changed_by).toLowerCase().includes(q);
  });

  return (
    <div>
      <div className="page-header">
        <div><h2>Audit Log</h2><p>Every important action, newest first. Read-only.</p></div>
        <button className="btn btn-secondary" onClick={load}><RefreshCw size={15} className={loading ? 'spin' : ''} /> Refresh</button>
      </div>

      <div style={{ display: 'flex', gap: 10, marginBottom: 14, flexWrap: 'wrap', alignItems: 'center' }}>
        <div style={{ position: 'relative', flex: 1, minWidth: 220, maxWidth: 320 }}>
          <Search size={15} style={{ position: 'absolute', left: 11, top: '50%', transform: 'translateY(-50%)', color: 'var(--text-muted)' }} />
          <input value={search} onChange={e => setSearch(e.target.value)} placeholder="Search action, table, user…" style={{ paddingLeft: 34 }} />
        </div>
        <select value={tableFilter} onChange={e => setTableFilter(e.target.value)} style={{ maxWidth: 200 }}>
          {tables.map(t => <option key={t} value={t}>{t === 'all' ? 'All tables' : t}</option>)}
        </select>
      </div>

      <div className="card">
        <div className="table-wrap">
          {loading ? <div className="empty-state"><RefreshCw size={24} className="spin" style={{ opacity: 0.4 }} /></div>
          : filtered.length === 0 ? <div className="empty-state"><ScrollText size={32} style={{ opacity: 0.3 }} /><p style={{ fontWeight: 600, marginTop: 8 }}>No audit entries</p></div>
          : (
            <table>
              <thead><tr><th>When</th><th>Action</th><th>Table</th><th>By</th><th>Details</th></tr></thead>
              <tbody>
                {filtered.map(l => (
                  <tr key={l.id}>
                    <td style={{ whiteSpace: 'nowrap', fontSize: 12 }}>{new Date(l.created_at).toLocaleDateString()}<div style={{ color: 'var(--text-muted)' }}>{new Date(l.created_at).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}</div></td>
                    <td><span className={`badge ${ACTION_CLS[l.action] ?? 'badge-muted'}`}>{l.action.replace(/_/g, ' ')}</span></td>
                    <td style={{ fontSize: 12.5 }}>{l.table_name}</td>
                    <td style={{ fontSize: 12.5 }}>{uName(l.changed_by)}</td>
                    <td style={{ fontSize: 11.5, color: 'var(--text-muted)', maxWidth: 280, fontFamily: 'var(--font-display)' }}>
                      {l.new_data ? JSON.stringify(l.new_data).slice(0, 80) : l.old_data ? JSON.stringify(l.old_data).slice(0, 80) : '—'}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>
      </div>
    </div>
  );
};

export default AuditLogPage;
