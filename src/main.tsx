import React from 'react';
import ReactDOM from 'react-dom/client';
import App from './App';
import { reloadOnStaleChunks } from './lib/staleChunks';
import './styles/globals.css';

// After a deploy, a page file of the old build is gone: reload once to pick
// up the new build instead of showing an error (ADMIN-AUTH-8).
reloadOnStaleChunks();

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>
);
