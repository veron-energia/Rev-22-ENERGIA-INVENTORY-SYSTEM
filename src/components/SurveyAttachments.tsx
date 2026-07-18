import React, { useEffect, useState, useRef } from 'react';
import {
  uploadSurveyAttachment, removeSurveyAttachment, downloadAttachment,
  signedUrl, isImage, prettySize, MAX_BYTES,
} from '../lib/surveyAttachments';
import { Paperclip, UploadCloud, Trash2, Download, FileText, FileSpreadsheet,
         RefreshCw, X, Eye, Lock, ImageIcon, CheckCircle2 } from 'lucide-react';

type Upload = { name: string; status: 'pending' | 'doing' | 'done' | 'error'; msg?: string };

const iconFor = (mime?: string | null) => {
  if (isImage(mime)) return <ImageIcon size={20} style={{ opacity: 0.55 }} />;
  if (mime?.includes('sheet') || mime?.includes('excel') || mime?.includes('csv'))
    return <FileSpreadsheet size={20} style={{ opacity: 0.55 }} />;
  return <FileText size={20} style={{ opacity: 0.55 }} />;
};

// Private bucket -> every preview needs its own short-lived signed URL.
const Thumb: React.FC<{ path: string; mime?: string | null }> = ({ path, mime }) => {
  const [url, setUrl] = useState<string | null>(null);
  const [failed, setFailed] = useState(false);
  useEffect(() => {
    let ok = true;
    if (isImage(mime)) signedUrl(path).then(u => { if (ok) { if (u) setUrl(u); else setFailed(true); } });
    return () => { ok = false; };
  }, [path, mime]);

  if (!isImage(mime) || failed) {
    return <div style={{ width: '100%', height: 96, background: 'var(--surface-2)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>{iconFor(mime)}</div>;
  }
  if (!url) {
    return <div style={{ width: '100%', height: 96, background: 'var(--surface-2)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}><RefreshCw size={14} className="spin" style={{ opacity: 0.4 }} /></div>;
  }
  return <img src={url} alt="" style={{ width: '100%', height: 96, objectFit: 'cover', display: 'block' }} />;
};

const SurveyAttachments: React.FC<{
  surveyId: string; storeId: string; attachments: any[];
  onChanged: () => void; readOnly?: boolean;
}> = ({ surveyId, storeId, attachments, onChanged, readOnly }) => {
  const fileRef = useRef<HTMLInputElement>(null);
  const [busy, setBusy] = useState(false);
  const [drag, setDrag] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [queue, setQueue] = useState<Upload[]>([]);
  const [lightbox, setLightbox] = useState<{ url: string; name: string } | null>(null);

  const handle = async (files: FileList | File[] | null) => {
    if (!files || readOnly) return;
    const list = Array.from(files as File[]);
    if (!list.length) return;
    setErr(null); setBusy(true);
    setQueue(list.map(f => ({ name: f.name, status: 'pending' })));

    let any = false;
    for (let i = 0; i < list.length; i++) {
      const f = list[i];
      setQueue(q => q.map((x, j) => j === i ? { ...x, status: 'doing' } : x));
      try {
        if (f.size > MAX_BYTES) throw new Error(`Larger than 10 MB (${prettySize(f.size)})`);
        await uploadSurveyAttachment(storeId, surveyId, f);
        setQueue(q => q.map((x, j) => j === i ? { ...x, status: 'done' } : x));
        any = true;
      } catch (e: any) {
        // One bad file shouldn't abandon the rest.
        setQueue(q => q.map((x, j) => j === i ? { ...x, status: 'error', msg: e?.message ?? 'Upload failed' } : x));
      }
    }
    setBusy(false);
    if (fileRef.current) fileRef.current.value = '';
    if (any) onChanged();
    setTimeout(() => setQueue(q => q.some(x => x.status === 'error') ? q : []), 2200);
  };

  const remove = async (a: any) => {
    if (!confirm(`Remove "${a.file_name}"? This cannot be undone.`)) return;
    setErr(null); setBusy(true);
    try { await removeSurveyAttachment(a.id); onChanged(); }
    catch (e: any) { setErr(e?.message ?? 'Could not remove the file.'); }
    setBusy(false);
  };

  const view = async (a: any) => {
    const u = await signedUrl(a.storage_path, 300);
    if (!u) { setErr('Could not open that file.'); return; }
    if (isImage(a.mime_type)) setLightbox({ url: u, name: a.file_name });
    else window.open(u, '_blank', 'noopener');
  };

  return (
    <div>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 8 }}>
        <label style={{ margin: 0, display: 'flex', alignItems: 'center', gap: 6 }}>
          <Paperclip size={13} /> Attachments
          {attachments.length > 0 && <span style={{ color: 'var(--text-muted)', fontWeight: 400 }}>({attachments.length})</span>}
        </label>
        {readOnly && (
          <span style={{ display: 'inline-flex', alignItems: 'center', gap: 4, fontSize: 11, color: 'var(--text-muted)' }}>
            <Lock size={11} /> View only
          </span>
        )}
      </div>

      {err && <div className="alert alert-danger" style={{ marginBottom: 8 }}><span>⚠</span><div>{err}</div></div>}

      {/* Drop zone — Owner/Manager only */}
      {!readOnly && (
        <>
          <input ref={fileRef} type="file" multiple hidden
            accept="image/*,application/pdf,.doc,.docx,.xls,.xlsx,.csv,.txt,.heic"
            onChange={e => handle(e.target.files)} />
          <div
            onClick={() => !busy && fileRef.current?.click()}
            onDragOver={e => { e.preventDefault(); setDrag(true); }}
            onDragLeave={() => setDrag(false)}
            onDrop={e => { e.preventDefault(); setDrag(false); handle(e.dataTransfer.files); }}
            style={{
              border: `2px dashed ${drag ? 'var(--primary)' : 'var(--border)'}`,
              background: drag ? 'var(--success-light)' : 'var(--surface-2)',
              borderRadius: 'var(--radius-sm)', padding: '18px 12px', textAlign: 'center',
              cursor: busy ? 'default' : 'pointer', transition: 'all .15s', marginBottom: 10,
            }}>
            <UploadCloud size={22} style={{ color: drag ? 'var(--primary)' : 'var(--text-muted)' }} />
            <div style={{ fontSize: 13, fontWeight: 600, marginTop: 6 }}>
              {busy ? 'Uploading…' : drag ? 'Drop to upload' : 'Drag files here, or click to browse'}
            </div>
            <div style={{ fontSize: 11.5, color: 'var(--text-muted)', marginTop: 2 }}>
              Photos, scans, PDFs or reports · up to 10 MB each · multiple allowed
            </div>
          </div>
        </>
      )}

      {/* Per-file progress */}
      {queue.length > 0 && (
        <div style={{ marginBottom: 10, display: 'flex', flexDirection: 'column', gap: 3 }}>
          {queue.map((u, i) => (
            <div key={i} style={{ display: 'flex', alignItems: 'center', gap: 6, fontSize: 12,
              color: u.status === 'error' ? 'var(--danger)' : 'var(--text-secondary)' }}>
              {u.status === 'doing' && <RefreshCw size={11} className="spin" />}
              {u.status === 'done' && <CheckCircle2 size={11} style={{ color: 'var(--success)' }} />}
              {u.status === 'error' && <X size={11} />}
              {u.status === 'pending' && <span style={{ width: 11 }} />}
              <span style={{ flex: 1, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{u.name}</span>
              {u.msg && <span style={{ fontSize: 11 }}>{u.msg}</span>}
            </div>
          ))}
        </div>
      )}

      {/* Grid */}
      {attachments.length === 0 ? (
        <div style={{ fontSize: 12.5, color: 'var(--text-muted)', textAlign: 'center', padding: '10px 0' }}>
          No files attached yet.
        </div>
      ) : (
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(150px, 1fr))', gap: 10 }}>
          {attachments.map(a => (
            <div key={a.id} style={{
              border: '1px solid var(--border)', borderRadius: 'var(--radius-sm)',
              overflow: 'hidden', background: 'var(--surface)',
            }}>
              <div style={{ position: 'relative', cursor: 'zoom-in' }} onClick={() => view(a)}>
                <Thumb path={a.storage_path} mime={a.mime_type} />
                <div style={{
                  position: 'absolute', inset: 0, display: 'flex', alignItems: 'center', justifyContent: 'center',
                  background: 'rgba(0,0,0,0)', transition: 'background .15s',
                }} onMouseEnter={e => (e.currentTarget.style.background = 'rgba(0,0,0,0.35)')}
                   onMouseLeave={e => (e.currentTarget.style.background = 'rgba(0,0,0,0)')}>
                  <Eye size={16} color="#fff" style={{ opacity: 0.9 }} />
                </div>
              </div>
              <div style={{ padding: '7px 8px' }}>
                <div title={a.file_name} style={{ fontSize: 12, fontWeight: 600, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{a.file_name}</div>
                <div style={{ fontSize: 10.5, color: 'var(--text-muted)', marginTop: 1 }}>
                  {prettySize(a.byte_size)} · {new Date(a.uploaded_at).toLocaleDateString()}
                </div>
                {a.uploaded_by_name && <div style={{ fontSize: 10, color: 'var(--text-muted)' }}>{a.uploaded_by_name}</div>}
                <div style={{ display: 'flex', gap: 4, marginTop: 6 }}>
                  <button className="btn btn-secondary btn-sm" style={{ flex: 1, padding: '3px 6px' }}
                    onClick={() => downloadAttachment(a.storage_path, a.file_name).catch(e => setErr(e?.message))}>
                    <Download size={11} />
                  </button>
                  {!readOnly && (
                    <button className="btn btn-danger btn-sm" style={{ flex: 1, padding: '3px 6px' }}
                      disabled={busy} onClick={() => remove(a)}>
                      <Trash2 size={11} />
                    </button>
                  )}
                </div>
              </div>
            </div>
          ))}
        </div>
      )}

      {lightbox && (
        <div onClick={() => setLightbox(null)} style={{
          position: 'fixed', inset: 0, background: 'rgba(0,0,0,0.85)', zIndex: 1100,
          display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center',
          padding: 24, cursor: 'zoom-out',
        }}>
          <img src={lightbox.url} alt="" style={{ maxWidth: '100%', maxHeight: 'calc(100% - 40px)', borderRadius: 6 }} />
          <div style={{ color: '#fff', fontSize: 12.5, marginTop: 10 }}>{lightbox.name}</div>
          <button className="btn btn-secondary btn-sm btn-icon" style={{ position: 'absolute', top: 16, right: 16 }}><X size={14} /></button>
        </div>
      )}
    </div>
  );
};

export default SurveyAttachments;
