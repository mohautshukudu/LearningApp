#!/usr/bin/env node
// Exports each web app's deck (web/<slug>/index.html) to MotAMot/Decks/Resources/<slug>.json
// for the native DeckStore. Run: node tools/export_decks.js
// Functions in the web specs (vis, pool, dyn) are evaluated once and stored as plain data.
const fs = require('fs');
const path = require('path');

const root = path.join(__dirname, '..');
const outDir = path.join(root, 'MotAMot', 'Decks', 'Resources');
fs.mkdirSync(outDir, { recursive: true });

// The web apps' answer normalisers, as regex rules the Swift side replays in order.
const NORM = {
  'desk-skills': [['command|cmd|⌘|control', 'ctrl'], ['option|⌥', 'alt'], ['windows|⊞|\\bwin\\b', 'win']],
  'slide-by-slide': [['command|cmd|⌘|control', 'ctrl'], ['option|⌥', 'alt']],
  'fret-by-fret': [['command|cmd|⌘|control', 'ctrl'], ['option|⌥', 'alt'], ['\\benter\\b', 'return']],
};
const KEYS = {
  'desk-skills': { prefix: 'e.g. Ctrl', keys: ['Ctrl+', 'Shift+', 'Alt+', 'Win+'] },
  'slide-by-slide': { prefix: 'e.g. Ctrl', keys: ['Ctrl+', 'Shift+', 'Alt+', 'F'] },
  'fret-by-fret': { prefix: 'e.g. Ctrl', keys: ['Ctrl+', 'Shift+', 'Alt+'] },
};

function load(slug) {
  const html = fs.readFileSync(path.join(root, 'web', slug, 'index.html'), 'utf8');
  const scripts = [...html.matchAll(/<script>([\s\S]*?)<\/script>/g)].map(m => m[1]).join('\n');
  const pre = scripts.slice(0, scripts.indexOf('/* ===================== shared engine'));
  global.window = {};
  const el = () => new Proxy(function () {}, {
    get: (t, k) => (k === Symbol.toPrimitive ? () => '' : k === 'style' ? {} : el()),
    apply: () => el(), set: () => true,
  });
  global.document = { getElementById: el, createElement: el, addEventListener() {}, querySelector: el,
    querySelectorAll: () => [], documentElement: el(), body: el(), head: el() };
  global.localStorage = { getItem() { return null; }, setItem() {} };
  global.navigator = {};
  (0, eval)(pre);
  return { html, A: window.APP };
}

function spec(sp, slug) {
  if (!sp) return null;
  if (sp.dyn) sp = Object.assign({}, sp, sp.dyn());
  const o = { p: sp.p, a: String(sp.a), t: sp.t };
  if (sp.acc) o.acc = sp.acc.map(String);
  if (sp.opts) o.opts = sp.opts.map(String);
  if (sp.pool) {
    const pool = typeof sp.pool === 'function' ? sp.pool() : sp.pool;
    o.pool = [...new Set(pool.map(String))].slice(0, 14);
  }
  if (sp.ph) o.ph = sp.ph;
  if (sp.sub) o.sub = sp.sub;
  if (sp.vis) o.vis = typeof sp.vis === 'function' ? sp.vis() : sp.vis;
  if (sp.matchOnly) o.matchOnly = true;
  if (sp.pc != null) o.pc = sp.pc;
  if (sp.toks) o.toks = sp.toks.map(String);
  if (sp.audio) o.audio = true;
  return o;
}

const index = [];
const slugs = ['py-by-py', 'desk-skills', 'slide-by-slide', 'atlas', 'fret-by-fret'];
for (const slug of slugs) {
  const { html, A } = load(slug);
  const theme = (/name="theme-color" content="(#[0-9A-Fa-f]{6})"/.exec(html) || [])[1] || '#3B5BDB';
  const desc = (/name="description" content="([^"]*)"/.exec(html) || [])[1] || '';
  const css = [...html.matchAll(/<style>([\s\S]*?)<\/style>/g)].map(m => m[1]).join('\n');
  const stages = A.stages.map(s => ({ name: s.name, start: s.start, end: s.end }));
  const cards = A.deck.map(c => ({
    id: c.id, cat: c.cat, grp: c.grp, ti: c.ti,
    teach: c.teach || '', why: c.why || '',
    f: spec(c.f, slug), r: spec(c.r, slug),
    hear: !!c.hear,
  }));
  const out = {
    slug, name: A.name, blurb: desc, theme, css,
    cats: A.cats, catOrder: Object.keys(A.cats), stages, cards,
    norm: NORM[slug] || [],
    pySquash: slug === 'py-by-py',
    keys: KEYS[slug] || null,
  };
  fs.writeFileSync(path.join(outDir, slug + '.json'), JSON.stringify(out));
  index.push({ slug, name: A.name, blurb: desc, theme, total: cards.length });
  console.log(slug, cards.length, 'cards', (fs.statSync(path.join(outDir, slug + '.json')).size / 1024).toFixed(0) + 'KB');
}
fs.writeFileSync(path.join(outDir, 'decks-index.json'), JSON.stringify(index));
