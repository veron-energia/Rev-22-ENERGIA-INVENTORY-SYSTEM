import React, { useState } from 'react';
import { useAuth } from '../context/AuthContext';
import { Leaf, LogIn } from 'lucide-react';

const LoginPage: React.FC = () => {
  const { signIn } = useAuth();
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [submitting, setSubmitting] = useState(false);
  const [err, setErr] = useState<string | null>(null);

  const envMissing = !import.meta.env.VITE_SUPABASE_URL || !import.meta.env.VITE_SUPABASE_ANON_KEY;

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setErr(null);
    setSubmitting(true);
    const { error } = await signIn(email.trim(), password);
    if (error) setErr(error);
    setSubmitting(false);
  };

  return (
    <div style={{ minHeight: '100vh', display: 'flex', alignItems: 'center', justifyContent: 'center', padding: 20, background: 'var(--bg)' }}>
      <div style={{ width: '100%', maxWidth: 400 }}>
        {/* Brand */}
        <div style={{ textAlign: 'center', marginBottom: 28 }}>
          <div style={{ display: 'inline-flex', alignItems: 'center', justifyContent: 'center', width: 52, height: 52, borderRadius: 14, background: 'var(--primary)', marginBottom: 14 }}>
            <Leaf size={26} color="#fff" />
          </div>
          <h1 style={{ fontSize: 26, color: 'var(--primary)' }}>Energia</h1>
          <p style={{ color: 'var(--text-muted)', fontSize: 13.5, marginTop: 2 }}>Inventory &amp; Sales System</p>
        </div>

        <div className="card" style={{ padding: 28 }}>
          {envMissing && (
            <div className="alert alert-danger">
              <span>⚠</span>
              <div>
                Supabase isn't configured. Create <strong>.env.local</strong> with your
                <code> VITE_SUPABASE_URL</code> and <code>VITE_SUPABASE_ANON_KEY</code>, then restart the dev server.
              </div>
            </div>
          )}

          <form onSubmit={handleSubmit} className="form-grid">
            <div className="form-group">
              <label>Email</label>
              <input type="email" value={email} onChange={e => setEmail(e.target.value)}
                placeholder="you@energia.sg" autoComplete="email" required autoFocus />
            </div>
            <div className="form-group">
              <label>Password</label>
              <input type="password" value={password} onChange={e => setPassword(e.target.value)}
                placeholder="••••••••" autoComplete="current-password" required />
            </div>

            {err && <div className="alert alert-danger" style={{ marginBottom: 0 }}><span>⚠</span><div>{err}</div></div>}

            <button type="submit" className="btn btn-primary" disabled={submitting || envMissing} style={{ width: '100%', marginTop: 4 }}>
              <LogIn size={16} /> {submitting ? 'Signing in…' : 'Sign in'}
            </button>
          </form>
        </div>

        <p style={{ textAlign: 'center', fontSize: 12, color: 'var(--text-muted)', marginTop: 18 }}>
          Accounts are created by an Owner or Manager.
        </p>
      </div>
    </div>
  );
};

export default LoginPage;
