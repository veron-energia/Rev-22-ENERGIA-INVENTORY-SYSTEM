import React, { useId, useRef, useState } from 'react';
import { Eye, EyeOff } from 'lucide-react';
import './password-input.css';

type Props = Omit<React.InputHTMLAttributes<HTMLInputElement>, 'type'> & {
  /** Toggling starts hidden on every mount and is never remembered. */
  value: string;
};

/**
 * A password field you can look at.
 *
 * Every field gets its own toggle — a password and its confirmation are two
 * separate decisions, and sharing one control would reveal a field the person
 * did not ask to see.
 *
 * Visibility is component state only. It is not stored, so a freshly opened
 * form always starts hidden, and nothing about the password reaches
 * localStorage, a URL or a log.
 */
export const PasswordInput: React.FC<Props> = ({ value, className, ...rest }) => {
  const [shown, setShown] = useState(false);
  const inputRef = useRef<HTMLInputElement | null>(null);
  const labelId = useId();

  const toggle = () => {
    const el = inputRef.current;
    // Read the caret before React re-renders, and put it back afterwards, so
    // revealing a password mid-word does not jump the cursor to the end.
    const start = el?.selectionStart ?? null;
    const end = el?.selectionEnd ?? null;
    setShown(s => !s);
    requestAnimationFrame(() => {
      const node = inputRef.current;
      if (!node) return;
      node.focus();
      if (start !== null && end !== null) {
        try { node.setSelectionRange(start, end); } catch { /* type may not support it */ }
      }
    });
  };

  return (
    <div className={`password-input${className ? ` ${className}` : ''}`}>
      <input
        {...rest}
        ref={inputRef}
        value={value}
        type={shown ? 'text' : 'password'}
      />
      <button
        type="button"                     /* never submits the form */
        className="password-input-toggle"
        onClick={toggle}
        aria-label={shown ? 'Hide password' : 'Show password'}
        aria-pressed={shown}
        title={shown ? 'Hide password' : 'Show password'}
        tabIndex={0}
      >
        {shown ? <EyeOff size={16} aria-hidden="true" /> : <Eye size={16} aria-hidden="true" />}
        <span id={labelId} className="sr-only">{shown ? 'Hide password' : 'Show password'}</span>
      </button>
    </div>
  );
};

export default PasswordInput;
