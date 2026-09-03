import React, { useEffect, useRef, useState } from 'react';
import QRCode from 'qrcode';
import { Copy, Download, Share2, Check } from 'lucide-react';

// Build public URLs from VITE_PUBLIC_APP_URL, falling back to the current
// origin so staging/production deployments stay correct without a rebuild.
export const publicAppUrl = (): string => {
  const env = (import.meta as any)?.env?.VITE_PUBLIC_APP_URL as string | undefined;
  return (env && env.replace(/\/+$/, '')) || (typeof window !== 'undefined' ? window.location.origin : '');
};

interface Props {
  url: string;
  title?: string;
  caption?: string;
  filename?: string;
}

// Renders a QR for `url` with Copy / Download PNG / Share controls.
const QRCodeCard: React.FC<Props> = ({ url, title, caption, filename }) => {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const [copied, setCopied] = useState(false);
  const [err, setErr] = useState<string | null>(null);

  useEffect(() => {
    if (!canvasRef.current || !url) return;
    QRCode.toCanvas(canvasRef.current, url, { width: 220, margin: 2, errorCorrectionLevel: 'M' })
      .catch(() => setErr('Could not render QR code'));
  }, [url]);

  const copy = async () => {
    try { await navigator.clipboard.writeText(url); setCopied(true); setTimeout(() => setCopied(false), 1500); }
    catch { /* clipboard blocked */ }
  };

  const download = () => {
    const c = canvasRef.current; if (!c) return;
    const a = document.createElement('a');
    a.href = c.toDataURL('image/png');
    a.download = (filename || 'energia-qr') + '.png';
    a.click();
  };

  const share = async () => {
    const nav = navigator as any;
    if (nav.share) { try { await nav.share({ title: title || 'Energia', url }); } catch { /* cancelled */ } }
    else copy();
  };

  const canShare = typeof navigator !== 'undefined' && !!(navigator as any).share;

  return (
    <div className="card" style={{ padding: 20, textAlign: 'center', maxWidth: 320 }}>
      {title && <h3 style={{ marginBottom: 6, fontSize: 15 }}>{title}</h3>}
      <div style={{ display: 'flex', justifyContent: 'center', padding: 8 }}>
        {err ? <p style={{ color: 'var(--danger)', fontSize: 13 }}>{err}</p>
             : <canvas ref={canvasRef} style={{ borderRadius: 10 }} />}
      </div>
      <div style={{ fontSize: 12, color: 'var(--text-muted)', wordBreak: 'break-all', margin: '6px 0 12px' }}>{url}</div>
      <div style={{ display: 'flex', gap: 8, justifyContent: 'center', flexWrap: 'wrap' }}>
        <button className="btn btn-secondary" onClick={copy} style={{ gap: 6 }}>
          {copied ? <Check size={15} /> : <Copy size={15} />}{copied ? 'Copied' : 'Copy Link'}
        </button>
        <button className="btn btn-secondary" onClick={download} style={{ gap: 6 }}>
          <Download size={15} /> PNG
        </button>
        {canShare && (
          <button className="btn btn-secondary" onClick={share} style={{ gap: 6 }}>
            <Share2 size={15} /> Share
          </button>
        )}
      </div>
      {caption && <p style={{ fontSize: 12.5, color: 'var(--text-secondary)', marginTop: 12 }}>{caption}</p>}
    </div>
  );
};

export default QRCodeCard;
