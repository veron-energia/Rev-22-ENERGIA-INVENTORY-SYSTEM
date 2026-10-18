import React from 'react';
import { isChunkLoadError } from '../lib/staleChunks';

/**
 * Catches a render fault and shows what went wrong.
 *
 * Without this, a single bad line in one component unmounts the entire app and
 * leaves a blank white page — no message, nothing in view, and the only way to
 * find the cause is to guess or open the browser console. That has cost real
 * time on this project.
 *
 * The rest of the app keeps working: only the section that failed is replaced.
 * The pages sit in one inside the menu layout, so the menu stays; moving to
 * another page clears the error (resetKey, or a key on the page).
 */
export class ErrorBoundary extends React.Component<
  { children: React.ReactNode; label?: string; resetKey?: string },
  { error: Error | null }
> {
  state: { error: Error | null } = { error: null };

  static getDerivedStateFromError(error: Error) {
    return { error };
  }

  componentDidCatch(error: Error, info: React.ErrorInfo) {
    // Kept in the console for anyone with devtools open.
    console.error('Render error', this.props.label ?? '', error, info.componentStack);
  }

  componentDidUpdate(prev: { resetKey?: string }) {
    if (this.state.error && prev.resetKey !== this.props.resetKey) this.setState({ error: null });
  }

  render() {
    if (!this.state.error) return this.props.children;

    // ADMIN-AUTH-8: a page file of an older build that is gone after a deploy.
    // Trying again asks for the same missing file; only a reload helps.
    if (isChunkLoadError(this.state.error)) {
      return (
        <div role="alert" style={{
          margin: 16, padding: 16, borderRadius: 8,
          background: 'var(--surface-2, #f3f4f6)', border: '1px solid var(--border, #e5e7eb)',
        }}>
          <div style={{ fontWeight: 700, marginBottom: 6 }}>A newer version of the app is ready</div>
          <div style={{ fontSize: 13, marginBottom: 10 }}>
            Reload the page to carry on. Anything you saved before is kept.
          </div>
          <button className="btn btn-primary btn-sm" onClick={() => window.location.reload()}>
            Reload page
          </button>
        </div>
      );
    }

    return (
      <div role="alert" style={{
        margin: 16, padding: 16, borderRadius: 8,
        background: 'var(--danger-light, #fdecec)',
        border: '1px solid var(--danger, #c0392b)',
      }}>
        <div style={{ fontWeight: 700, marginBottom: 6 }}>
          Something went wrong{this.props.label ? ` in ${this.props.label}` : ''}
        </div>
        <div style={{ fontSize: 13, marginBottom: 10 }}>
          Nothing has been saved or changed. Close this and try again — if it keeps
          happening, send this message to whoever maintains the system.
        </div>
        <pre style={{
          fontSize: 11.5, whiteSpace: 'pre-wrap', wordBreak: 'break-word',
          background: 'rgba(0,0,0,0.05)', padding: 8, borderRadius: 4, margin: 0,
        }}>{this.state.error.message}</pre>
        <button className="btn btn-secondary btn-sm" style={{ marginTop: 10 }}
          onClick={() => this.setState({ error: null })}>
          Try again
        </button>
      </div>
    );
  }
}
