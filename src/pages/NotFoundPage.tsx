import React from 'react';
import { useNavigate } from 'react-router-dom';
import { useAuth } from '../context/AuthContext';
import { Leaf, ArrowLeft } from 'lucide-react';

const NotFoundPage: React.FC = () => {
  const navigate = useNavigate();
  const { session } = useAuth();

  const goBack = () => {
    // Return to the previous page; if there's no history, go to the dashboard
    // when signed in, otherwise the login page.
    if (window.history.length > 1) navigate(-1);
    else navigate(session ? '/' : '/login', { replace: true });
  };

  return (
    <div style={{
      minHeight: '100vh', display: 'flex', alignItems: 'center', justifyContent: 'center',
      background: 'var(--bg, #f6f8f7)', padding: 24,
    }}>
      <div style={{
        background: 'var(--surface, #fff)', border: '1px solid var(--border, #e5e7eb)',
        borderRadius: 'var(--radius, 16px)', padding: '48px 40px', maxWidth: 460, width: '100%',
        textAlign: 'center', boxShadow: '0 10px 40px rgba(15,23,42,0.06)',
      }}>
        <div style={{
          display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
          width: 56, height: 56, borderRadius: 14, background: 'var(--primary, #2f7d5b)', marginBottom: 18,
        }}>
          <Leaf size={28} color="#fff" />
        </div>
        <div style={{ fontSize: 15, fontWeight: 700, color: 'var(--primary, #2f7d5b)', letterSpacing: '0.02em' }}>Energia</div>

        <div style={{ fontSize: 64, fontWeight: 800, color: 'var(--text, #111827)', lineHeight: 1, marginTop: 18 }}>404</div>
        <h1 style={{ fontSize: 20, margin: '10px 0 8px', color: 'var(--text, #111827)' }}>Page Not Found</h1>
        <p style={{ fontSize: 14, color: 'var(--text-secondary, #6b7280)', lineHeight: 1.6, margin: '0 auto 26px', maxWidth: 360 }}>
          The page you're looking for doesn't exist or may have been moved. Let's get you back on track.
        </p>

        <button className="btn btn-primary" onClick={goBack} style={{ display: 'inline-flex', alignItems: 'center', gap: 8 }}>
          <ArrowLeft size={16} /> Go Back
        </button>
      </div>
    </div>
  );
};

export default NotFoundPage;
