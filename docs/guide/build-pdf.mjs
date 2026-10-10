#!/usr/bin/env node
// Builds one PDF per language from docs/guide/<lang>/*.md: a cover, a table of contents with page numbers, then the
// chapters in file order, each on a new page.
//
//   node docs/guide/build-pdf.mjs [--lang en|az|tr|ru] [--out <dir>]      (default: every language, docs/guide/dist)
//
// Needs `markdown-it` and `playwright` (with its Chromium) where Node can require them, e.g. `npm i -D markdown-it
// playwright` in a scratch folder and NODE_PATH pointing at its node_modules. The TOC's page numbers come from a
// first rendering read back with `pdftotext` (poppler-utils); without it the TOC has no numbers.
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import { createRequire } from 'node:module';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const require = createRequire(import.meta.url);
const MarkdownIt = require('markdown-it');
const { chromium } = require('playwright');

const here = path.dirname(fileURLToPath(import.meta.url));
const args = process.argv.slice(2);
const option = (name, fallback) => {
  const at = args.indexOf(`--${name}`);
  return at >= 0 ? args[at + 1] : fallback;
};
const languages = option('lang', null) ? [option('lang')] : ['en', 'az', 'tr', 'ru'];
const outDir = path.resolve(option('out', path.join(here, 'dist')));

const TEXTS = {
  en: { title: 'Clomni Mobile SDK', subtitle: 'Integration guide', contents: 'Contents', version: 'SDK 1.0.2' },
  az: { title: 'Clomni Mobile SDK', subtitle: 'İnteqrasiya təlimatı', contents: 'Mündəricat', version: 'SDK 1.0.2' },
  tr: { title: 'Clomni Mobile SDK', subtitle: 'Entegrasyon kılavuzu', contents: 'İçindekiler', version: 'SDK 1.0.2' },
  ru: { title: 'Clomni Mobile SDK', subtitle: 'Руководство по интеграции', contents: 'Содержание', version: 'SDK 1.0.2' },
};
const GREEN = '#10A670';

// GitHub's heading anchors: lower case, punctuation dropped, spaces to hyphens. Links in the Markdown use them.
const slug = text => text.trim().toLowerCase().replace(/[^\p{L}\p{N}\s_-]/gu, '').replace(/\s/g, '-');
const escapeHtml = text => text.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');

function renderChapter(md, file, chapterId, headings, markers) {
  const dir = path.dirname(file);
  const env = {};
  const tokens = md.parse(fs.readFileSync(file, 'utf8'), env);
  const seen = new Map();
  for (let i = 0; i < tokens.length; i += 1) {
    const token = tokens[i];
    if (token.type === 'heading_open') {
      const text = tokens[i + 1].content.replace(/`/g, '');
      const base = slug(text);
      const count = seen.get(base) || 0;
      seen.set(base, count + 1);
      const level = Number(token.tag.slice(1));
      const id = level === 1 ? chapterId : `${chapterId}--${count ? `${base}-${count}` : base}`;
      token.attrSet('id', id);
      if (level <= 2) {
        const marker = `zzm${headings.length}zz`;
        headings.push({ id, level, text, marker });
        if (markers) {
          // An invisible, unique word the first rendering's text is searched for, to learn the heading's page.
          const Token = md.core.State.prototype.Token;
          const span = new Token('html_inline', '', 0);
          span.content = `<span class="marker">${marker}</span>`;
          tokens[i + 1].children.push(span);
        }
      }
    }
    // A blockquote that opens with **Yol:** / **Path:** is a navigation path in a console we have no screenshot of.
    if (token.type === 'blockquote_open' && /^\*\*(Yol|Path):\*\*/.test(tokens[i + 2]?.content || '')) {
      token.attrSet('class', 'path');
    }
    if (token.type === 'inline') {
      for (const child of token.children) {
        if (child.type === 'image') {
          child.attrSet('src', pathToFileURL(path.resolve(dir, child.attrGet('src'))).href);
        }
        if (child.type === 'link_open') {
          const href = child.attrGet('href');
          const local = href.match(/^(?:(\d\d-[\w-]+)\.md)?(?:#(.+))?$/);
          if (local && (local[1] || local[2])) {
            const target = local[1] ? `ch-${local[1]}` : chapterId;
            child.attrSet('href', `#${local[2] ? `${target}--${local[2]}` : target}`);
          }
        }
      }
    }
  }
  return md.renderer.render(tokens, md.options, env);
}

function buildHtml(lang, pages, markers) {
  const md = new MarkdownIt({ html: false, linkify: false, typographer: false });
  const files = fs.readdirSync(path.join(here, lang)).filter(f => /^\d\d-.*\.md$/.test(f)).sort();
  const headings = [];
  const chapters = files.map(f => {
    const chapterId = `ch-${f.replace(/\.md$/, '')}`;
    return `<section class="chapter">${renderChapter(md, path.join(here, lang, f), chapterId, headings, markers)}</section>`;
  });
  const t = TEXTS[lang];
  const toc = headings.map(h => {
    const page = pages ? String(pages.get(h.marker) ?? '') : '000';
    return `<a class="toc toc${h.level}" href="#${h.id}"><span class="t">${escapeHtml(h.text)}</span>` +
      `<span class="dots"></span><span class="p${pages ? '' : ' hidden'}">${page}</span></a>`;
  }).join('\n');
  const date = new Date().toISOString().slice(0, 10);
  return { headings, html: `<!doctype html>
<html lang="${lang}"><head><meta charset="utf-8"><title>${t.title}: ${t.subtitle}</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;600;700&family=JetBrains+Mono:wght@400;600&display=swap" rel="stylesheet">
<style>
  @page { size: A4; margin: 18mm 15mm 20mm 15mm; }
  html { font-family: Inter, "DejaVu Sans", sans-serif; font-size: 10pt; line-height: 1.5; color: #1D2939; }
  body { margin: 0; }
  h1, h2, h3, h4 { color: ${GREEN}; line-height: 1.25; break-after: avoid; }
  h1 { font-size: 21pt; margin: 0 0 10pt; }
  h2 { font-size: 14pt; margin: 18pt 0 6pt; }
  h3 { font-size: 11.5pt; margin: 14pt 0 4pt; }
  h4 { font-size: 10.5pt; margin: 12pt 0 4pt; }
  p, ul, ol { margin: 0 0 7pt; }
  li { margin: 2pt 0; }
  a { color: inherit; text-decoration: underline; text-decoration-color: #98A2B3; }
  code { font-family: "JetBrains Mono", "DejaVu Sans Mono", monospace; font-size: 8.6pt; background: #F2F4F7;
         border-radius: 3px; padding: 0 2px; }
  pre { background: #F5F7F9; border: 1px solid #E4E7EC; border-radius: 5px; padding: 6pt 6pt; margin: 0 0 9pt;
        white-space: pre-wrap; overflow-wrap: anywhere; break-inside: avoid; }
  pre code { background: none; padding: 0; font-size: 7pt; line-height: 1.45; }
  table { border-collapse: collapse; width: 100%; margin: 0 0 10pt; font-size: 8.8pt; break-inside: auto; }
  th, td { border: 1px solid #D0D5DD; padding: 4pt 6pt; text-align: left; vertical-align: top; }
  th { background: #F2F4F7; font-weight: 600; }
  tr { break-inside: avoid; }
  blockquote { margin: 0 0 9pt; padding: 6pt 10pt; background: #F5F7F9; border-left: 3px solid #98A2B3; }
  blockquote p:last-child { margin-bottom: 0; }
  blockquote.path { background: #F2F4F7; border-left: 3px solid ${GREEN}; break-inside: avoid; }
  blockquote.path p { margin-bottom: 3pt; }
  blockquote.path code { background: none; padding: 0; }
  blockquote.path p:first-child code { font-size: 8.8pt; overflow-wrap: anywhere; }
  blockquote.path a { overflow-wrap: anywhere; }
  img { display: block; max-width: 100%; max-height: 150mm; margin: 4pt 0 10pt; border: 1px solid #E4E7EC;
        border-radius: 4px; break-inside: avoid; }
  p:has(> img:only-child) { break-inside: avoid; }
  .chapter { break-before: page; }
  .marker { position: absolute; font-size: 2px; color: #fff; }
  .cover { height: 250mm; display: flex; flex-direction: column; justify-content: center; }
  .cover .title { font-size: 34pt; font-weight: 700; color: ${GREEN}; }
  .cover .subtitle { font-size: 18pt; margin-top: 6pt; }
  .cover .meta { margin-top: 28pt; color: #667085; font-size: 10pt; }
  .contents { break-before: page; }
  .contents h1 { margin-bottom: 14pt; }
  .toc { display: flex; align-items: baseline; text-decoration: none; color: #1D2939; }
  .toc1 { font-weight: 600; margin-top: 7pt; }
  .toc2 { padding-left: 14pt; font-size: 9.2pt; color: #344054; }
  .toc .dots { flex: 1; border-bottom: 1px dotted #98A2B3; margin: 0 5pt; }
  .toc .p { min-width: 18pt; text-align: right; font-variant-numeric: tabular-nums; }
  .hidden { visibility: hidden; }
</style></head><body>
<div class="cover"><div class="title">${t.title}</div><div class="subtitle">${t.subtitle}</div>
<div class="meta">${t.version} · ${date}<br>github.com/clomni/clomni-mobile-sdk</div></div>
<div class="contents"><h1>${t.contents}</h1>
${toc}</div>
${chapters.join('\n')}
</body></html>` };
}

async function render(browser, html, pdfPath, title) {
  const htmlPath = path.join(os.tmpdir(), `clomni-guide-${process.pid}.html`);
  fs.writeFileSync(htmlPath, html);
  const page = await browser.newPage();
  await page.goto(pathToFileURL(htmlPath).href, { waitUntil: 'networkidle', timeout: 120000 });
  await page.evaluate(() => document.fonts.ready);
  await page.pdf({
    path: pdfPath, format: 'A4', printBackground: true, preferCSSPageSize: true, displayHeaderFooter: true,
    headerTemplate: '<span></span>',
    footerTemplate: `<div style="width:100%;font-size:7.5pt;color:#667085;padding:0 15mm;display:flex;
      justify-content:space-between;font-family:Inter,'DejaVu Sans',sans-serif"><span>${escapeHtml(title)}</span>
      <span><span class="pageNumber"></span> / <span class="totalPages"></span></span></div>`,
  });
  await page.close();
  fs.unlinkSync(htmlPath);
}

// Each heading's page, from the markers of the first rendering.
function markerPages(pdfPath) {
  let text;
  try {
    text = execFileSync('pdftotext', ['-layout', pdfPath, '-'], { encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 });
  } catch {
    console.warn('pdftotext not found: the table of contents has no page numbers');
    return null;
  }
  const pages = new Map();
  text.split('\f').forEach((pageText, index) => {
    for (const match of pageText.matchAll(/zzm\d+zz/g)) if (!pages.has(match[0])) pages.set(match[0], index + 1);
  });
  return pages;
}

fs.mkdirSync(outDir, { recursive: true });
const browser = await chromium.launch();
try {
  for (const lang of languages) {
    const t = TEXTS[lang];
    const pdfPath = path.join(outDir, `Clomni-Mobile-SDK-Guide-${lang}.pdf`);
    const title = `${t.title} · ${t.subtitle}`;
    const first = buildHtml(lang, null, true);
    await render(browser, first.html, pdfPath, title);
    const pages = markerPages(pdfPath);
    if (pages) {
      const missing = first.headings.filter(h => !pages.has(h.marker)).map(h => h.text);
      if (missing.length) console.warn(`no page found for: ${missing.join(', ')}`);
      await render(browser, buildHtml(lang, pages, false).html, pdfPath, title);
    }
    console.log(`${pdfPath} (${Math.round(fs.statSync(pdfPath).size / 1024)} KB)`);
  }
} finally {
  await browser.close();
}
