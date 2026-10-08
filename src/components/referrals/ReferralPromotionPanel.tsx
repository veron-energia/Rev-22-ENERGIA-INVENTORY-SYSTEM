import React, { useCallback, useEffect, useMemo, useState } from 'react';
import { supabase } from '../../lib/supabase';
import { Modal } from '../ui';
import { SearchSelect } from '../SearchSelect';
import { ExcelExportButton } from '../ExcelExport';
import { sgDate, sgDayOf, statusNote, rewardItems, windowLabel, notYetVisited, notYetVisitedLine, friendStatus, emptyReportNote } from '../../lib/referral/campaign.mjs';
import type { CampaignInfo } from '../../lib/referral/campaign.mjs';
import { RefreshCw, Gift, ChevronDown, ChevronRight, Undo2, Plus, Trash2 } from 'lucide-react';

interface Friend { customer_id: string; name: string; phone: string | null; referred_on: string; first_visit_on: string | null; counted: boolean; }
interface Reward {
  reward_id: string; tier: number; friends_counted: number; given_at: string; given_by_name: string | null;
  store_id: string; store_name: string | null; note: string | null;
  items: { product_id: string; product_name: string; quantity: number; use_no: string | null }[];
}
interface ReferrerRow {
  referrer_customer_id: string; name: string; phone: string | null; is_affiliate: boolean;
  /** 404: friends referred in the window who have not visited yet (absent before 404). */
  counted: number; not_yet_visited?: number;
  tier_reached: number | null; next_tier: number | null; to_next: number | null;
  reward: Reward | null; friends: Friend[];
}
interface Report { campaign: CampaignInfo; campaigns: { code: string; title: string; starts_on: string; ends_on: string }[]; referrers: ReferrerRow[]; }
interface Line { product_id: string; quantity: string; }

/** Every row, a thousand at a time (the API stops at a thousand without
 *  saying so), as fetchAllRows in lib/supabasePaging does. Kept here so the
 *  Affiliates page's own imports stay what they were. */
async function readAll<T>(build: () => any): Promise<T[]> {
  const rows: T[] = [];
  for (let offset = 0; ; offset += 1000) {
    const { data, error } = await build().order('id', { ascending: true }).range(offset, offset + 999);
    if (error) throw new Error(error.message);
    rows.push(...((data ?? []) as T[]));
    if ((data ?? []).length < 1000) return rows;
  }
}

/**
 * A referral promotion's report (398, the Owner's rules of 6 Oct 2026; 404,
 * the Owner's rule of 8 Oct 2026): every referrer with a friend listed, the
 * friends counted (a first visit to the centre in the window, whenever they
 * were referred, the referral recorded by its last day; past customers
 * never; a form through the centre's link dated the day it was sent), the
 * friends referred in the window who have not visited yet, the tier reached
 * and the next one, each friend on opening the row, and the reward. After the
 * window ends an Owner or Manager marks the reward given: the products, their
 * quantities and the store they come from, which takes them out of that
 * store's stock as stock uses. The Owner alone can undo one. Owner/Manager
 * only; the database refuses anyone else.
 */
const ReferralPromotionPanel: React.FC<{ isOwner: boolean }> = ({ isOwner }) => {
  const [code, setCode] = useState('');
  const [report, setReport] = useState<Report | null>(null);
  const [loading, setLoading] = useState(true);
  const [err, setErr] = useState<string | null>(null);
  const [success, setSuccess] = useState<string | null>(null);
  const [open, setOpen] = useState<Record<string, boolean>>({});
  const [onlyCounted, setOnlyCounted] = useState(false);

  const load = useCallback(async () => {
    setLoading(true); setErr(null);
    const { data, error } = await supabase.rpc('referral_campaign_report', { p_campaign: code || null });
    setLoading(false);
    if (error) { setErr(error.message); return; }
    setReport(data as Report);
  }, [code]);
  useEffect(() => { void load(); }, [load]);

  // ── Mark reward given ──
  const [giveFor, setGiveFor] = useState<ReferrerRow | null>(null);
  const [stores, setStores] = useState<{ id: string; name: string }[]>([]);
  const [products, setProducts] = useState<{ id: string; name: string; sku: string | null }[]>([]);
  const [storeId, setStoreId] = useState('');
  const [stock, setStock] = useState<Record<string, number>>({});
  const [lines, setLines] = useState<Line[]>([{ product_id: '', quantity: '1' }]);
  const [note, setNote] = useState('');
  const [giveErr, setGiveErr] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const openGive = async (r: ReferrerRow) => {
    setGiveFor(r); setGiveErr(null); setNote(''); setLines([{ product_id: '', quantity: '1' }]); setStoreId(''); setStock({});
    if (stores.length === 0) {
      const { data } = await supabase.from('stores').select('id,name').is('deleted_at', null).eq('is_active', true).order('name');
      setStores((data as any[]) ?? []);
    }
    if (products.length === 0) {
      try {
        setProducts(await readAll(() => supabase.from('products').select('id,name,sku').is('deleted_at', null)));
      } catch (e: any) { setGiveErr(e.message); }
    }
  };
  useEffect(() => {
    if (!storeId) { setStock({}); return; }
    let live = true;
    readAll<{ product_id: string; current_qty: number }>(() =>
      supabase.from('store_inventory').select('id,product_id,current_qty').eq('store_id', storeId).gt('current_qty', 0))
      .then(rows => { if (live) setStock(Object.fromEntries(rows.map(r => [r.product_id, Number(r.current_qty)]))); })
      .catch(e => { if (live) setGiveErr(e.message); });
    return () => { live = false; };
  }, [storeId]);

  // Only products the chosen store holds can be taken out of it.
  const options = useMemo(() => products.filter(p => (stock[p.id] ?? 0) > 0).map(p => ({
    value: p.id, label: p.name, sublabel: `${p.sku ?? ''} · ${stock[p.id]} in stock`, search: `${p.name} ${p.sku ?? ''}`,
  })), [products, stock]);

  const submitGive = async () => {
    if (!giveFor || !report) return;
    if (!storeId) { setGiveErr('Choose the store the reward comes from.'); return; }
    const r = rewardItems(lines);
    if (!r.items) { setGiveErr(r.error); return; }
    for (const it of r.items) {
      if (it.quantity > (stock[it.product_id] ?? 0)) {
        const name = products.find(p => p.id === it.product_id)?.name ?? 'A product';
        setGiveErr(`Only ${stock[it.product_id] ?? 0} of "${name}" in stock at this store.`); return;
      }
    }
    setBusy(true); setGiveErr(null);
    const { data, error } = await supabase.rpc('give_referral_campaign_reward', {
      p_campaign: report.campaign.code, p_referrer_customer_id: giveFor.referrer_customer_id,
      p_store_id: storeId, p_items: r.items, p_note: note.trim() || null,
    });
    setBusy(false);
    if (error) { setGiveErr(error.message); return; }
    const uses = ((data as any)?.items ?? []).map((i: any) => i.use_no).filter(Boolean).join(', ');
    setSuccess(`Reward recorded for ${giveFor.name} (tier ${(data as any)?.tier}). Taken out of ${(data as any)?.store_name}'s stock${uses ? `: ${uses}` : ''}.`);
    setGiveFor(null); void load();
  };

  // ── Undo (Owner) ──
  const [undoFor, setUndoFor] = useState<ReferrerRow | null>(null);
  const [undoReason, setUndoReason] = useState('');
  const [undoStock, setUndoStock] = useState(true);
  const [undoErr, setUndoErr] = useState<string | null>(null);
  const submitUndo = async () => {
    if (!undoFor?.reward) return;
    if (!undoReason.trim()) { setUndoErr('A reason is required.'); return; }
    setBusy(true); setUndoErr(null);
    const { error } = await supabase.rpc('void_referral_campaign_reward', {
      p_reward_id: undoFor.reward.reward_id, p_reason: undoReason.trim(), p_return_stock: undoStock,
    });
    setBusy(false);
    if (error) { setUndoErr(error.message); return; }
    setSuccess(`The reward for ${undoFor.name} was undone${undoStock ? ` and its products put back into ${undoFor.reward.store_name}'s stock` : ''}. It can be marked again.`);
    setUndoFor(null); void load();
  };

  const c = report?.campaign;
  const rows = (report?.referrers ?? []).filter(r => !onlyCounted || r.counted > 0);
  const final = c?.status === 'final';
  const tiers = (c?.tiers ?? []).join(' / ');

  return (
    <div>
      <div style={{ display: 'flex', gap: 8, alignItems: 'center', flexWrap: 'wrap', marginBottom: 12 }}>
        {(report?.campaigns?.length ?? 0) > 1 && (
          <select value={code || c?.code || ''} onChange={e => setCode(e.target.value)} style={{ maxWidth: 260 }} aria-label="Promotion">
            {report!.campaigns.map(x => <option key={x.code} value={x.code}>{x.title} ({windowLabel(x.starts_on, x.ends_on)})</option>)}
          </select>
        )}
        <label style={{ display: 'flex', alignItems: 'center', gap: 6, fontSize: 13, cursor: 'pointer' }}>
          <input type="checkbox" checked={onlyCounted} onChange={e => setOnlyCounted(e.target.checked)} style={{ width: 'auto' }} />
          Only referrers with a friend counted
        </label>
        <span style={{ flex: 1 }} />
        {report && <ExcelExportButton rows={rows} filename={`referral-promotion-${c?.code ?? ''}`} sheetName="Referral promotion"
          columns={[
            { header: 'Referrer', value: r => r.name },
            { header: 'Phone', value: r => r.phone ?? '' },
            { header: 'Affiliate', value: r => r.is_affiliate ? 'Yes' : 'No' },
            { header: 'Friends Counted', value: r => r.counted },
            { header: 'Referred In Window, Not Yet Visited', value: r => notYetVisited(r) },
            { header: 'Tier Reached', value: r => r.tier_reached ?? '' },
            { header: 'Next Tier', value: r => r.next_tier ?? '' },
            { header: 'More To Next Tier', value: r => r.to_next ?? '' },
            { header: 'Reward Given', value: r => r.reward ? sgDayOf(r.reward.given_at) : '' },
            { header: 'Reward', value: r => r.reward ? r.reward.items.map(i => `${i.quantity} × ${i.product_name}`).join('; ') : '' },
            { header: 'Friends Counted (names)', value: r => r.friends.filter(f => f.counted).map(f => f.name).join('; ') },
          ]} />}
        <button className="btn btn-secondary" onClick={() => void load()}><RefreshCw size={15} className={loading ? 'spin' : ''} /> Refresh</button>
      </div>

      {err && <div className="alert alert-danger"><span>⚠</span><div>{err}</div></div>}
      {success && <div className="alert alert-info" role="status"><span>✓</span><div>{success}</div></div>}
      {c && (
        <div className={`alert ${final ? 'alert-info' : 'alert-warning'}`} data-status={c.status}>
          <span>{final ? '✓' : 'ℹ️'}</span>
          <div>
            <strong>{c.title}</strong> — {statusNote(c)}<br />
            <span style={{ fontSize: 12.5 }}>
              A Tier 1 friend counts when their first visit to the centre is in the promotion, whenever they were referred (the referral must be
              recorded by its last day; links without a referral date use the date the customer was created). Friends referred during the
              promotion who have not visited yet are listed too, not counted. A past customer (a paid or part-paid invoice dated before the
              promotion started) is neither counted nor listed; cancelled, refunded, unpaid and FOC invoices do not make one. A visit through
              the centre's QR link counts on the day the form was sent, not the date written on it, so a friend's first visit here can differ
              from the Customers page. Tiers: {tiers}. The reward is for the highest tier reached only.
            </span>
          </div>
        </div>
      )}

      <div className="card" style={{ padding: 0, overflow: 'auto' }}>
        <table className="table" style={{ width: '100%' }}>
          <thead><tr>
            <th></th><th>Referrer</th><th>Phone</th>
            <th style={{ textAlign: 'right' }}>Friends counted</th><th style={{ textAlign: 'right' }}>Tier reached</th><th>Next tier</th><th>Reward</th><th></th>
          </tr></thead>
          <tbody>
            {loading && !report && <tr><td colSpan={8} style={{ textAlign: 'center', padding: 20, color: 'var(--text-muted)' }}>Loading…</td></tr>}
            {report && rows.length === 0 && <tr><td colSpan={8} style={{ textAlign: 'center', padding: 20, color: 'var(--text-muted)' }}>{emptyReportNote(report.referrers?.length ?? 0, onlyCounted)}</td></tr>}
            {rows.map(r => {
              const isOpen = !!open[r.referrer_customer_id];
              const waitingLine = notYetVisitedLine(notYetVisited(r), c?.status);
              return (
                <React.Fragment key={r.referrer_customer_id}>
                  <tr>
                    <td style={{ width: 30 }}>
                      <button className="btn btn-secondary btn-sm btn-icon" aria-label={`Friends of ${r.name}`} aria-expanded={isOpen}
                        onClick={() => setOpen(o => ({ ...o, [r.referrer_customer_id]: !o[r.referrer_customer_id] }))}>
                        {isOpen ? <ChevronDown size={13} /> : <ChevronRight size={13} />}
                      </button>
                    </td>
                    <td><strong>{r.name}</strong>{r.is_affiliate && <span className="badge badge-primary" style={{ marginLeft: 6, fontSize: 10 }}>Affiliate</span>}
                      {waitingLine && <div style={{ fontSize: 11, color: 'var(--text-muted)' }}>{waitingLine}</div>}</td>
                    <td style={{ fontFamily: 'var(--font-display)', fontSize: 13 }}>{r.phone ?? '—'}</td>
                    <td style={{ textAlign: 'right', fontWeight: 700 }}>{r.counted}</td>
                    <td style={{ textAlign: 'right' }}>{r.tier_reached ?? '—'}</td>
                    <td>{r.next_tier != null ? `${r.next_tier} (${r.to_next} more)` : <span style={{ color: 'var(--text-muted)' }}>Top tier</span>}</td>
                    <td style={{ fontSize: 12.5 }}>
                      {r.reward
                        ? <><span className="badge badge-success">Given · tier {r.reward.tier}</span>
                            <div style={{ color: 'var(--text-muted)', marginTop: 2 }}>
                              {sgDayOf(r.reward.given_at)}{r.reward.given_by_name ? ` by ${r.reward.given_by_name}` : ''} · {r.reward.store_name}<br />
                              {r.reward.items.map(i => `${i.quantity} × ${i.product_name}${i.use_no ? ` (${i.use_no})` : ''}`).join(', ')}
                            </div></>
                        : r.tier_reached != null
                          ? <span className={`badge ${final ? 'badge-accent' : 'badge-muted'}`}>{final ? 'To give' : 'Provisional'}</span>
                          : '—'}
                    </td>
                    <td style={{ textAlign: 'right', whiteSpace: 'nowrap' }}>
                      {!r.reward && r.tier_reached != null && (
                        <button className="btn btn-primary btn-sm" disabled={!final}
                          title={final ? `Mark the tier ${r.tier_reached} reward given` : 'Rewards are given after the promotion ends'}
                          onClick={() => void openGive(r)} style={{ gap: 4 }}><Gift size={13} /> Mark reward given</button>
                      )}
                      {r.reward && isOwner && (
                        <button className="btn btn-secondary btn-sm" title="Undo this reward (Owner)" style={{ gap: 4 }}
                          onClick={() => { setUndoFor(r); setUndoReason(''); setUndoStock(true); setUndoErr(null); }}><Undo2 size={13} /> Undo</button>
                      )}
                    </td>
                  </tr>
                  {isOpen && (
                    <tr>
                      <td></td>
                      <td colSpan={7} style={{ background: 'var(--surface-2)' }}>
                        <table style={{ fontSize: 12 }}>
                          <thead><tr><th>Friend</th><th>Phone</th><th>Referred</th>
                            <th title="For the promotion: a form through the centre's QR link is dated the day it was sent">First visit (promotion)</th>
                            <th>Counts</th></tr></thead>
                          <tbody>
                            {r.friends.map(f => (
                              <tr key={f.customer_id}>
                                <td>{f.name}</td>
                                <td style={{ fontFamily: 'var(--font-display)' }}>{f.phone ?? '—'}</td>
                                <td>{sgDate(f.referred_on)}</td>
                                <td>{f.first_visit_on ? sgDate(f.first_visit_on) : 'Not yet'}</td>
                                <td>{f.counted ? <span className="badge badge-success">Yes</span>
                                  : <span className="badge badge-muted">{friendStatus(f, c?.status)}</span>}</td>
                              </tr>
                            ))}
                          </tbody>
                        </table>
                      </td>
                    </tr>
                  )}
                </React.Fragment>
              );
            })}
          </tbody>
        </table>
      </div>

      {giveFor && c && (
        <Modal title={`Mark reward given — ${giveFor.name}`} maxWidth={560} confirmClose onClose={() => setGiveFor(null)}
          footer={<>
            <button className="btn btn-secondary" onClick={() => setGiveFor(null)}>Cancel</button>
            <button className="btn btn-primary" disabled={busy} onClick={() => void submitGive()}>{busy ? 'Saving…' : 'Record reward and take stock out'}</button>
          </>}>
          <div className="form-grid">
            <div style={{ fontSize: 13 }}>
              {giveFor.name} reached <strong>tier {giveFor.tier_reached}</strong> with {giveFor.counted} friends counted in the {c.title}.
              The reward is for this tier only. The products below are taken out of the store&apos;s stock as stock uses
              (&ldquo;{c.reward_reason ?? 'Referral reward'} — {giveFor.name}&rdquo;), and the reward is recorded, together.
            </div>
            {giveErr && <div className="alert alert-danger" style={{ marginBottom: 0 }}><span>⚠</span><div>{giveErr}</div></div>}
            <div className="form-group" style={{ marginBottom: 0 }}>
              <label>Store the reward comes from *</label>
              <select value={storeId} onChange={e => { setStoreId(e.target.value); setLines([{ product_id: '', quantity: '1' }]); }}>
                <option value="">— Select —</option>
                {stores.map(s => <option key={s.id} value={s.id}>{s.name}</option>)}
              </select>
            </div>
            {storeId && (
              <div className="form-group" style={{ marginBottom: 0 }}>
                <label>Products *</label>
                {lines.map((l, i) => (
                  <div key={i} style={{ display: 'flex', gap: 6, alignItems: 'center', marginBottom: 6 }}>
                    <div style={{ flex: 1 }}>
                      <SearchSelect options={options} value={l.product_id} placeholder="Search a product this store holds…"
                        exclude={lines.filter((_, j) => j !== i).map(x => x.product_id).filter(Boolean)}
                        emptyLabel="Nothing in stock matches"
                        onChange={v => setLines(ls => ls.map((x, j) => j === i ? { ...x, product_id: v } : x))} />
                    </div>
                    <input type="number" min={1} step={1} value={l.quantity} aria-label="Quantity" style={{ width: 80 }}
                      onChange={e => setLines(ls => ls.map((x, j) => j === i ? { ...x, quantity: e.target.value } : x))} />
                    <button type="button" className="btn btn-secondary btn-sm btn-icon" aria-label="Remove line" disabled={lines.length === 1}
                      onClick={() => setLines(ls => ls.filter((_, j) => j !== i))}><Trash2 size={13} /></button>
                  </div>
                ))}
                <button type="button" className="btn btn-secondary btn-sm" style={{ gap: 4 }}
                  onClick={() => setLines(ls => [...ls, { product_id: '', quantity: '1' }])}><Plus size={13} /> Add product</button>
              </div>
            )}
            <div className="form-group" style={{ marginBottom: 0 }}>
              <label>Note</label>
              <input value={note} onChange={e => setNote(e.target.value)} placeholder="Optional — kept with the reward and its stock uses" />
            </div>
          </div>
        </Modal>
      )}

      {undoFor?.reward && (
        <Modal title={`Undo reward — ${undoFor.name}`} maxWidth={480} confirmClose onClose={() => setUndoFor(null)}
          footer={<>
            <button className="btn btn-secondary" onClick={() => setUndoFor(null)}>Cancel</button>
            <button className="btn btn-danger" disabled={busy || !undoReason.trim()} onClick={() => void submitUndo()}>{busy ? 'Saving…' : 'Undo reward'}</button>
          </>}>
          <div className="form-grid">
            <div style={{ fontSize: 13 }}>
              For a reward recorded by mistake. It stays on record, marked undone, and can then be marked again.
            </div>
            {undoErr && <div className="alert alert-danger" style={{ marginBottom: 0 }}><span>⚠</span><div>{undoErr}</div></div>}
            <label style={{ display: 'flex', alignItems: 'center', gap: 8, cursor: 'pointer' }}>
              <input type="checkbox" checked={undoStock} onChange={e => setUndoStock(e.target.checked)} style={{ width: 'auto' }} />
              <span style={{ fontSize: 13 }}>Put {undoFor.reward.items.map(i => `${i.quantity} × ${i.product_name}`).join(', ')} back into {undoFor.reward.store_name}&apos;s stock
                (untick if the products did leave the store)</span>
            </label>
            <div className="form-group" style={{ marginBottom: 0 }}>
              <label>Reason *</label>
              <textarea rows={2} value={undoReason} onChange={e => setUndoReason(e.target.value)} />
            </div>
          </div>
        </Modal>
      )}
    </div>
  );
};

export default ReferralPromotionPanel;
