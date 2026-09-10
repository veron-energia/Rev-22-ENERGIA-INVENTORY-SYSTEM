import React, { useEffect, useState } from 'react';
import { supabase } from '../../lib/supabase';
export function TransferNoteHistory({ requestId, showLines = false }: { requestId: string; showLines?: boolean }) {
  const [data, setData] = useState<any>(null), [error, setError] = useState(''), [retry, setRetry] = useState(0);
  useEffect(() => {
    let live = true; setData(null); setError('');
    supabase.rpc('stock_transfer_details', { p_request_id: requestId }).then(({ data, error }) => {
      if (!live) return;
      if (error) setError(error.message || 'Transfer notes could not be loaded.'); else setData(data);
    });
    return () => { live = false; };
  }, [requestId, retry]);
  return <section aria-label="Shared transfer history" className="stock-transfer-notes">
    <h4>Shared transfer history</h4>
    {error ? <div role="alert">{error} <button className="btn btn-secondary" onClick={() => setRetry(n => n + 1)}>Retry notes</button></div> : !data ? <p role="status">Loading transfer history…</p> : <>
      {showLines && <><p>{String(data.status).replace(/_/g, ' ')} · Destination: {data.destination}</p>{data.lines.map((l: any) => <p key={l.id}><strong>{l.product}</strong> {l.sku} · {l.quantity} {l.uom}{l.sources?.map((s: any) => ` · ${s.name}: ${s.quantity}`).join('')}</p>)}</>}
      {!data.notes.length && <p>No notes were recorded for this transfer.</p>}
      <ol>{data.notes.map((n: any) => <li key={n.id}>
        <div><strong>{n.stage}</strong> · {n.author} · {n.at ? new Date(n.at).toLocaleString('en-GB', { timeZone: 'Asia/Singapore' }) + ' SGT' : 'Time unavailable'}</div>
        {n.product && <div>{n.product}</div>}<p style={{ whiteSpace: 'pre-wrap', overflowWrap: 'anywhere' }}>{n.text}</p>
      </li>)}</ol>
    </>}
  </section>;
}
