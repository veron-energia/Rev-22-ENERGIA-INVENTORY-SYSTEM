import React, { useEffect, useState, useRef } from 'react';
import { useAuth } from '../context/AuthContext';
import { isOwnerOrManager } from '../types';
import {
  uploadSurveyAttachment, removeSurveyAttachment, downloadAttachment,
  signedUrl, isImage, prettySize, MAX_BYTES,
} from '../lib/surveyAttachments';
import { Paperclip, Upload, Trash2, Download, FileText, RefreshCw, X } from 'lucide-react';

// Thumbnail for image attachments. The bucket is private, so each preview
// needs its own short-lived signed URL.
const Thumb: React.FC<{ path: string; onOpen: () => void }> = ({ path, onOpen }) => {
  const [url, setUrl] = useState<string | null>(null);
  useEffect(() => { let ok = true; signedUrl(path).then(u => { if (ok) setUrl(u); }); return () => { ok = false; }; }, [path]);
  if (!url) return <div style={{ width: 46, height: 46, borderRadius: 6, background: 'var(--surface-2)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}><RefreshCw size={12} className="spin" style={{ opacity: 0.4 }} /></div>;
  return <img src={url} alt="" onClick={onOpen}
    style={{ width: 46, height: 46, objectFit: 'cover', borderRadius: 6, cursor: 'zoom-in', border: '1px solid var(--border)' }} />;
};

const SurveyAttachments: React.FC<{
  surveyId: string; storeId: string; attachments: any[];
  onChanged: () => void; readOnly?: boolean;
}> = ({ surveyId, storeId, attachments, onChanged, readOnly }) => {
  const { profile } = useAuth();
  const canDeleteAny = isOwnerOrManager(profile?.role);
  const fileRef = useRef<HTMLInputElement>(null);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [progress, setProgress] = useState('');
  const [lightbox, setLightbox] = useState<string | null>(null);

  const pick = async (files: FileList | null) => {
    if (!files?.length) return;
    setErr(null); setBusy(true);
    const list = Array.from(files);
    let done = 0;
    for (const f of list) {
      setProgress(`Uploading ${done + 1} of ${list.length}…`);
      try {
        if (f.size > MAX_BYTES) throw new Error(`${f.name} is larger than 10 MB.`);
        await uploadSurveyAttachment(storeId, surveyId, f);
        done++;
      } catch (e: any) {
        setErr(e?.message ?? `Could not upload ${f.name}.`);
        break;   // stop on first failure; already-uploaded files are kept
      }
    }
    setBusy(false); setProgress('');
    if (fileRef.current) fileRef.current.value = '';
    if (done > 0) onChanged();
  };

  const remove = async (a: any) => {
    if (!confirm(`Remove "${a.file_name}"? This cannot be undone.`)) return;
    setErr(null); setBusy(true);
    try { await removeSurveyAttachment(a.id); onChanged(); }
    catch (e: any) { setErr(e?.message ?? 'Could not remove the file.'); }
    setBusy(false);
  };

  const openImage = async (path: string) => {
    const u = await signedUrl(path, 300);
    if (u) setLightbox(u);
  };

  return (
    <div>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 6 }}>
        <label style={{ margin: 0, display: 'flex', alignItems: 'center', gap: 6 }}>
          <Paperclip size={13} /> Attachments {attachments.length > 0 && <span style={{ color: 'var(--text-muted)', fontWeight: 400 }}>({attachments.length})</span>}
        </label>
        {!readOnly && (
          <>
            <input ref={fileRef} type="file" multiple hidden
              accept="image/*,application/pdf,.doc,.docx,.xls,.xlsx,.csv,.txt,.heic"
              onChange={e => pick(e.target.files)} />
            <button className="btn btn-secondary btn-sm" disabled={busy} onClick={() => fileRef.current?.click()}>
              {busy ? <><RefreshCw size={12} className="spin" /> {progress || 'Working…'}</> : <><Upload size={12} /> Add Files</>}
            </button>
          </>
        )}
      </div>

      {err && <div className="alert alert-danger" style={{ marginBottom: 8 }}><span>⚠</span><div>{err}</div></div>}

      {attachments.length === 0 ? (
        <div style={{ fontSize: 12.5, color: 'var(--text-muted)', padding: '8px 0' }}>
          No files yet. {!readOnly && 'Photos, scans or reports — up to 10 MB each.'}
        </div>
      ) : (
        <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
          {attachments.map(a => (
            <div key={a.id} style={{
              display: 'flex', alignItems: 'center', gap: 10, padding: 8,
              border: '1px solid var(--border)', borderRadius: 'var(--radius-sm)',
            }}>
              {isImage(a.mime_type)
                ? <Thumb path={a.storage_path} onOpen={() => openImage(a.storage_path)} />
                : <div style={{ width: 46, height: 46, borderRadius: 6, background: 'var(--surface-2)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                    <FileText size={18} style={{ opacity: 0.5 }} />
                  </div>}
              <div style={{ flex: 1, minWidth: 0 }}>
                <div style={{ fontSize: 13, fontWeight: 600, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{a.file_name}</div>
                <div style={{ fontSize: 11, color: 'var(--text-muted)' }}>
                  {prettySize(a.byte_size)}{a.uploaded_by_name ? ` · ${a.uploaded_by_name}` : ''} · {new Date(a.uploaded_at).toLocaleDateString()}
                </div>
              </div>
              <div style={{ display: 'flex', gap: 4 }}>
                <button className="btn btn-secondary btn-sm" title="Download"
                  onClick={() => downloadAttachment(a.storage_path, a.file_name).catch(e => setErr(e?.message))}>
                  <Download size={12} />
                </button>
                {!readOnly && (canDeleteAny || a.uploaded_by === profile?.id) && (
                  <button className="btn btn-danger btn-sm" title="Remove" disabled={busy} onClick={() => remove(a)}>
                    <Trash2 size={12} />
                  </button>
                )}
              </div>
            </div>
          ))}
        </div>
      )}

      {lightbox && (
        <div onClick={() => setLightbox(null)} style={{
          position: 'fixed', inset: 0, background: 'rgba(0,0,0,0.8)', zIndex: 1100,
          display: 'flex', alignItems: 'center', justifyContent: 'center', padding: 24, cursor: 'zoom-out',
        }}>
          <button className="btn btn-secondary btn-sm btn-icon" style={{ position: 'absolute', top: 16, right: 16 }}><X size={14} /></button>
          <img src={lightbox} alt="" style={{ maxWidth: '100%', maxHeight: '100%', borderRadius: 6 }} />
        </div>
      )}
    </div>
  );
};

export default SurveyAttachments;
