import React from 'react';
import { useNavigate } from 'react-router-dom';
import { useAuth } from '../context/AuthContext';
import { Leaf, Home } from 'lucide-react';

const NotFoundPage: React.FC = () => {
  const navigate = useNavigate();
  const { session } = useAuth();

  // ADMIN-AUTH-18: "Go Back" went one step back in the browser's history,
  // which could leave the app altogether (a link opened in a new tab, a
  // bookmark). The button now goes to the dashboard, or to sign in.
  const goHome = () => navigate(session ? '/' : '/login', { replace: true });

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

        <button className="btn btn-primary" onClick={goHome} style={{ display: 'inline-flex', alignItems: 'center', gap: 8 }}>
          <Home size={16} aria-hidden="true" /> {session ? 'Go to dashboard' : 'Go to sign in'}
        </button>
      </div>
    </div>
  );
};

export default NotFoundPage;
