/**
 * The affiliate portal's navigation must not be nameable by an ad blocker.
 *
 * An affiliate on a laptop reported seeing no sidebar AND no hamburger — while
 * the dashboard itself rendered fine. The code, the stylesheet and the deployed
 * bundle were all verified correct at every width, so nothing in the app was
 * wrong. The pattern of what vanished is what gave it away:
 *
 *     hidden:  <aside  class="affiliate-sidebar">
 *              <header class="affiliate-mobile-header">
 *     visible: <main class="affiliate-main">, <div class="affiliate-content">,
 *              <div class="affiliate-stat-grid">, …
 *
 * Everything hidden was a structural element whose class contained the word
 * "affiliate"; everything that survived was a div or a main. That is the
 * signature of a content blocker's cosmetic filter. "affiliate" is among the
 * most heavily targeted tokens in the public filter lists — affiliate banners
 * are an ad category — and the generic rules are element-scoped, e.g.
 *
 *     aside[class*="affiliate"], header[class*="affiliate"] { display: none !important }
 *
 * which hides exactly those two and spares the divs. The person was left with
 * no navigation and no way to sign out, and a refresh could never fix it.
 *
 * The portal chrome was renamed off that token (portal-*, and the sidebar is a
 * <nav>, which blockers avoid hiding because it breaks sites). This test keeps
 * it that way: it is far too easy to name a new affiliate component
 * "affiliate-something" and quietly hand the filter lists a target again.
 *
 *   node scripts/ui/tests/portal-chrome-is-not-blockable.test.mjs
 */
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join } from 'node:path';

// Tokens the public filter lists target. Not exhaustive — these are the ones
// that would plausibly appear in this codebase's own class names.
const BAIT = ['affiliate', 'sponsor', 'banner', 'promo-ad', 'advert'];

// Structural elements a cosmetic filter will hide. A div is rarely targeted on
// its own; these are.
const STRUCTURAL = ['aside', 'header', 'nav', 'section', 'footer'];

function walk(dir, out = []) {
  for (const e of readdirSync(dir)) {
    const p = join(dir, e);
    if (statSync(p).isDirectory()) { if (e !== 'node_modules') walk(p, out); }
    else if (/\.(tsx|jsx)$/.test(e)) out.push(p);
  }
  return out;
}

const problems = [];

for (const file of walk('src')) {
  const text = readFileSync(file, 'utf8');

  // A structural element carrying a bait token in its class is the exact shape
  // that was hidden in production.
  for (const tag of STRUCTURAL) {
    const re = new RegExp(`<${tag}\\b[^>]*className=["\`]([^"\`]*)["\`]`, 'g');
    for (const m of text.matchAll(re)) {
      const cls = m[1];
      for (const bait of BAIT) {
        if (cls.includes(bait)) {
          const line = text.slice(0, m.index).split('\n').length;
          problems.push(`${file}:${line}  <${tag} className="${cls}"> contains "${bait}"`);
        }
      }
    }
  }
}

// And the stylesheet must not define layout rules under those names either —
// a rule is only reachable if some element wears the class, but a leftover
// definition is how the name creeps back.
const css = readFileSync('src/styles/globals.css', 'utf8');
for (const bait of BAIT) {
  const re = new RegExp(`\\.(${bait}[a-z0-9-]*)\\s*[,{]`, 'g');
  for (const m of css.matchAll(re)) {
    const line = css.slice(0, m.index).split('\n').length;
    problems.push(`src/styles/globals.css:${line}  selector .${m[1]} is named after a blocked token`);
  }
}

if (problems.length) {
  console.error('FAIL: portal chrome an ad blocker could hide\n');
  for (const p of problems) console.error('  ' + p);
  console.error(`\n${problems.length} problem(s). Rename off the blocked token — the portal's`);
  console.error('navigation is the one thing that must never be hideable: without it a');
  console.error('signed-in affiliate cannot navigate or even sign out.');
  process.exit(1);
}

console.log('PASS: no portal chrome is named after a token ad blockers target.');
