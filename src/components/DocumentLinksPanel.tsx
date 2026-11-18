import React, { useCallback, useEffect, useRef, useState } from 'react';
import { supabase } from '../lib/supabase';
import { useAuth } from '../context/AuthContext';
import { isOwnerOrManager } from '../types';
import { displayDateTime } from '../lib/calendarDates';

/**
 * "Links sent" (security audit L7, 18 Nov 2026): the customer links made for
 * one invoice, special sale or rental, for Owners and Managers only. A link
 * can be withdrawn here: the stored PDF copy is deleted first (the link
 * stops opening it), and only then is the withdrawal recorded. A copy stored
 * again under a withdrawn name is shown as such and can be withdrawn again
 * (the user, 18 Nov 2026: show it, do not block it).
 */
export type DocLinkKind = 'invoice' | 'special_sale' | 'rental';

type LinkRow = {
  send_id: string | null;
  pdf_path: string;
  sent_at: string;
  channel: 'whatsapp' | 'email' | 'download' | null;
  sent_to: string | null;
  sent_by_name: string | null;
  status: 'sent' | 'failed';
  copy_present: boolean;
  withdrawn_at: string | null;
  withdrawn_by_name: string | null;
};

const CHANNEL: Record<string, string> = { whatsapp: 'WhatsApp', email: 'Email', download: 'Download' };
/** The start of the server's refusal while a copy is still stored (523). */
const STILL_STORED = 'The PDF copy is still there';

const DocumentLinksPanel: React.FC<{
  docKind: DocLinkKind;
  docId: string;
  /** Change it after a send, so a link sent while the detail is open shows up. */
  reloadKey?: number | string;
}> = ({ docKind, docId, reloadKey }) => {
  const { profile } = useAuth();
  const allowed = isOwnerOrManager(profile?.role);
  const [rows, setRows] = useState<LinkRow[] | null>(null);
  const [loadErr, setLoadErr] = useState<string | null>(null);
  const [busyPath, setBusyPath] = useState<string | null>(null);
  const [actionErr, setActionErr] = useState<string | null>(null);
  // A copy deleted whose withdrawal could not be recorded: it can be recorded again.
  const [unrecorded, setUnrecorded] = useState<string | null>(null);
  const seq = useRef(0);

  const load = useCallback(async () => {
    const mine = ++seq.current;
    const { data, error } = await supabase.rpc('document_links', { p_doc_kind: docKind, p_doc_id: docId });
    if (mine !== seq.current) return;
    if (error) { setRows(null); setLoadErr(error.message || 'The list could not be read.'); return; }
    setLoadErr(null);
    setRows((data ?? []) as LinkRow[]);
  }, [docKind, docId]);

  useEffect(() => {
    if (!allowed) return;
    setRows(null); setLoadErr(null); setActionErr(null); setUnrecorded(null);
    void load();
    return () => { seq.current++; };
  }, [allowed, load, reloadKey]);

  if (!allowed) return null;

  // Record a withdrawal (the copy is already deleted). The server refuses while
  // the copy is still stored. When it fails, the list is read again: only a copy
  // no longer stored is said to be deleted, and offered to be recorded again (a
  // delete can answer without error and delete nothing, and a copy can be stored
  // again meanwhile); otherwise the server's answer is shown alone.
  const record = async (path: string): Promise<boolean> => {
    const { error } = await supabase.rpc('withdraw_document_link', { p_doc_kind: docKind, p_doc_id: docId, p_pdf_path: path });
    if (!error) { setUnrecorded(null); return true; }
    const why = (error.message || 'no reason given').replace(/\.\s*$/, '');
    const { data, error: listErr } = await supabase.rpc('document_links', { p_doc_kind: docKind, p_doc_id: docId });
    const list = (data ?? []) as LinkRow[];
    if (!listErr) { setRows(list); setLoadErr(null); }
    const gone = !listErr && !list.some(x => x.pdf_path === path && x.copy_present);
    setUnrecorded(gone ? path : null);
    // When the list says the copy is gone, a "still there" answer from just before is
    // not repeated: the later reading is the true one.
    setActionErr(gone ? (why.startsWith(STILL_STORED) ? 'The withdrawal could not be recorded.' : `The withdrawal could not be recorded: ${why}.`)
      : `${why}.`);
    return false;
  };

  const withdraw = async (r: LinkRow) => {
    if (busyPath) return;
    if (!window.confirm('Withdraw this link? It stops opening the PDF. A PDF the customer already opened or saved stays with them. This cannot be undone; to give them a new link, send the document again.')) return;
    setBusyPath(r.pdf_path); setActionErr(null); setUnrecorded(null);
    try {
      // The server only records a withdrawal once the copy is gone.
      const { error: rmErr } = await supabase.storage.from('invoice-pdfs').remove([r.pdf_path]);
      if (rmErr) { setActionErr(`The PDF copy could not be deleted, so the link still opens (${rmErr.message}).`); return; }
      if (await record(r.pdf_path)) await load();
    } catch (e: any) {
      setActionErr(e?.message || 'The link could not be withdrawn.');
    } finally {
      setBusyPath(null);
    }
  };

  const recordAgain = async () => {
    if (busyPath || !unrecorded) return;
    const path = unrecorded;
    setBusyPath(path); setActionErr(null);
    try {
      if (await record(path)) await load();
    } catch (e: any) {
      setActionErr(e?.message || 'The withdrawal could not be recorded.');
    } finally {
      setBusyPath(null);
    }
  };

  const state = (r: LinkRow) => {
    if (!r.withdrawn_at) return r.copy_present ? 'Link open until it expires' : 'Copy no longer stored';
    const done = `Withdrawn ${displayDateTime(r.withdrawn_at)}${r.withdrawn_by_name ? ` by ${r.withdrawn_by_name}` : ''}`;
    return r.copy_present ? `${done}, but a copy is stored under this name again and the link opens it` : done;
  };

  return (
    <div data-testid="document-links-panel" style={{ border: '1px solid var(--border)', borderRadius: 'var(--radius-sm)', padding: '10px 12px', background: 'var(--surface-2)', fontSize: 12.5 }}>
      <div style={{ fontWeight: 700, marginBottom: 4 }}>Links sent</div>
      {loadErr && <div className="alert alert-danger" role="alert" data-testid="document-links-error">The links could not be read: {loadErr}</div>}
      {actionErr && <div className="alert alert-danger" role="alert" data-testid="document-links-action-error">{actionErr}
        {unrecorded && <> The copy is deleted, so the link no longer opens it.{' '}
          <button className="btn btn-secondary btn-sm" disabled={!!busyPath} onClick={recordAgain}>Record the withdrawal</button></>}
      </div>}
      {!loadErr && rows === null && <div style={{ color: 'var(--text-muted)' }}>Loading…</div>}
      {!loadErr && rows !== null && rows.length === 0 && <div style={{ color: 'var(--text-muted)' }}>No links were sent.</div>}
      {!loadErr && rows !== null && rows.map(r => (
        <div key={`${r.send_id ?? 'old'}-${r.pdf_path}-${r.sent_at}`} data-testid="document-link-row"
          style={{ display: 'flex', gap: 8, alignItems: 'center', flexWrap: 'wrap', padding: '4px 0', borderTop: '1px solid var(--border)' }}>
          <div style={{ flex: '1 1 260px', minWidth: 0, overflowWrap: 'anywhere' }}>
            <div><strong>{displayDateTime(r.sent_at)}</strong> · {r.send_id === null ? 'Sent before the send log' : (r.channel ? CHANNEL[r.channel] : 'Unknown')}
              {r.sent_to ? <> · to {r.sent_to}</> : null}{r.sent_by_name ? <> · by {r.sent_by_name}</> : null}
              {r.status === 'failed' ? <> · the send failed (the copy was made)</> : null}</div>
            <div style={{ color: 'var(--text-muted)' }}>{state(r)}</div>
          </div>
          {r.copy_present && (
            <button className="btn btn-secondary btn-sm" disabled={!!busyPath} onClick={() => withdraw(r)}
              title="Stop this link working now">{busyPath === r.pdf_path ? 'Withdrawing…' : 'Withdraw'}</button>)}
        </div>
      ))}
    </div>
  );
};

export default DocumentLinksPanel;
