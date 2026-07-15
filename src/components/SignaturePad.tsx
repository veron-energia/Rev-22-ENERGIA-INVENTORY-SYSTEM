import React, { useRef, useState, useEffect } from 'react';
import { Eraser } from 'lucide-react';

// Simple signature pad. Works with mouse, stylus and finger (pointer events).
// Emits a base64 PNG whenever the stroke ends.
const SignaturePad: React.FC<{ value: string; onChange: (dataUrl: string) => void; height?: number }> = ({ value, onChange, height = 150 }) => {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const drawing = useRef(false);
  const [empty, setEmpty] = useState(!value);

  // Size the canvas to its container, accounting for device pixel ratio.
  useEffect(() => {
    const cv = canvasRef.current;
    if (!cv) return;
    const ratio = window.devicePixelRatio || 1;
    const w = cv.offsetWidth;
    cv.width = w * ratio;
    cv.height = height * ratio;
    const ctx = cv.getContext('2d');
    if (ctx) {
      ctx.scale(ratio, ratio);
      ctx.lineWidth = 2;
      ctx.lineCap = 'round';
      ctx.lineJoin = 'round';
      ctx.strokeStyle = '#111';
    }
  }, [height]);

  const pos = (e: React.PointerEvent) => {
    const cv = canvasRef.current!;
    const r = cv.getBoundingClientRect();
    return { x: e.clientX - r.left, y: e.clientY - r.top };
  };

  const start = (e: React.PointerEvent) => {
    e.preventDefault();
    const ctx = canvasRef.current?.getContext('2d');
    if (!ctx) return;
    drawing.current = true;
    const p = pos(e);
    ctx.beginPath();
    ctx.moveTo(p.x, p.y);
    canvasRef.current?.setPointerCapture(e.pointerId);
  };
  const move = (e: React.PointerEvent) => {
    if (!drawing.current) return;
    e.preventDefault();
    const ctx = canvasRef.current?.getContext('2d');
    if (!ctx) return;
    const p = pos(e);
    ctx.lineTo(p.x, p.y);
    ctx.stroke();
  };
  const end = () => {
    if (!drawing.current) return;
    drawing.current = false;
    const cv = canvasRef.current;
    if (!cv) return;
    setEmpty(false);
    onChange(cv.toDataURL('image/png'));
  };

  const clear = () => {
    const cv = canvasRef.current;
    const ctx = cv?.getContext('2d');
    if (!cv || !ctx) return;
    ctx.clearRect(0, 0, cv.width, cv.height);
    setEmpty(true);
    onChange('');
  };

  return (
    <div>
      <div style={{ position: 'relative', border: '1px solid var(--border)', borderRadius: 'var(--radius-sm)', background: '#fff', overflow: 'hidden' }}>
        <canvas
          ref={canvasRef}
          style={{ width: '100%', height, display: 'block', touchAction: 'none', cursor: 'crosshair' }}
          onPointerDown={start} onPointerMove={move} onPointerUp={end} onPointerLeave={end}
        />
        {empty && (
          <div style={{
            position: 'absolute', inset: 0, display: 'flex', alignItems: 'center', justifyContent: 'center',
            pointerEvents: 'none', color: 'var(--text-muted)', fontSize: 13,
          }}>Sign here</div>
        )}
      </div>
      <div style={{ display: 'flex', justifyContent: 'flex-end', marginTop: 6 }}>
        <button type="button" className="btn btn-secondary btn-sm" onClick={clear}><Eraser size={12} /> Clear</button>
      </div>
    </div>
  );
};

export default SignaturePad;
