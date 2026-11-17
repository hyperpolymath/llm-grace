// Three-way inventory: for each skill, what does each version contain that another lacks?
//
//   bun tools/inventory.mjs
//
// Versions looked for:
//   original     originals/raw/<name>.paste.txt
//   zip-summary  originals/zip-summaries/<name>/SKILL.md
//   v2           originals/v2/<name>/**/*.md   (drop the reviewer's pack here when available)
//
// A line of version A counts as "missing from B" when fewer than half of its content
// words (4+ letters) occur anywhere in B. Crude on purpose: it flags material to look
// at; it does not judge quality.
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const WORD = /[A-Za-zÀ-ÿ][A-Za-zÀ-ÿ'-]{3,}/g;
const NL = /\r\n|[\n\r\v\f\x1c-\x1e\x85\u2028\u2029]/;
const splitlines = (t) => (t === "" ? [] : t.replace(new RegExp(`(${NL.source})$`), "").split(NL));
const WS = "\\t\\n\\v\\f\\r \\x1c-\\x1f\\x85\\xa0\\u1680\\u2000-\\u200a\\u2028\\u2029\\u202f\\u205f\\u3000";
const strip = (s) => s.replace(new RegExp(`^[${WS}]+|[${WS}]+$`, "g"), "");
const nWords = (t) => strip(t).split(new RegExp(`[${WS}]+`)).filter(Boolean).length;
const read = (p) => fs.readFileSync(p, "utf8").replace(/\r\n?/g, "\n"); // universal newlines, like Python's read_text
const words = (text) => new Set((text.match(WORD) ?? []).map((w) => w.toLowerCase()));
const byCodePoint = (a, b) => (a < b ? -1 : a > b ? 1 : 0);

function rglobMd(dir) {
  const out = [];
  const rec = (d, parts) => {
    for (const e of fs.readdirSync(d, { withFileTypes: true })) {
      if (e.isDirectory()) rec(path.join(d, e.name), [...parts, e.name]);
      else if (e.name.endsWith(".md")) out.push({ p: path.join(d, e.name), parts: [...parts, e.name] });
    }
  };
  rec(dir, []);
  // Python sorts Path objects component by component
  return out.sort((a, b) => {
    for (let i = 0; i < Math.min(a.parts.length, b.parts.length); i++) {
      const c = byCodePoint(a.parts[i], b.parts[i]);
      if (c) return c;
    }
    return a.parts.length - b.parts.length;
  }).map((x) => x.p);
}

function versions(name) {
  const v = {};
  let p = path.join(ROOT, "originals/raw", `${name}.paste.txt`);
  if (fs.existsSync(p)) v.original = splitlines(read(p)).slice(1).join("\n");
  p = path.join(ROOT, "originals/zip-summaries", name, "SKILL.md");
  if (fs.existsSync(p)) v["zip-summary"] = read(p);
  const d = path.join(ROOT, "originals/v2", name);
  if (fs.existsSync(d)) v.v2 = rglobMd(d).map(read).join("\n");
  return v;
}

function missing(a, b) {
  const vocab = words(b);
  const out = [];
  for (const line of splitlines(a)) {
    const w = words(line);
    if (w.size >= 3) {
      let hit = 0;
      for (const x of w) if (vocab.has(x)) hit++;
      if (hit / w.size < 0.5) out.push(strip(line));
    }
  }
  return out;
}

const rawDir = path.join(ROOT, "originals/raw"), zipDir = path.join(ROOT, "originals/zip-summaries"), v2Dir = path.join(ROOT, "originals/v2");
const nameSet = new Set();
for (const f of fs.readdirSync(rawDir)) if (f.endsWith(".paste.txt")) nameSet.add(f.replace(".paste.txt", ""));
if (fs.existsSync(zipDir)) for (const f of fs.readdirSync(zipDir)) nameSet.add(f);
if (fs.existsSync(v2Dir)) for (const f of fs.readdirSync(v2Dir)) nameSet.add(f);
const names = [...nameSet].sort(byCodePoint);

const outdir = path.join(ROOT, "reports/inventory");
fs.mkdirSync(outdir, { recursive: true });
console.log(`${"skill".padEnd(38)} ${"versions".padEnd(30)} lines only in each (vs every other version present)`);
for (const name of names) {
  const v = versions(name);
  const keys = Object.keys(v);
  const rep = [`# Inventory: ${name}`, "", "Versions found: " + keys.map((k) => `${k} (${nWords(v[k])} words)`).join(", "), ""];
  const summary = [];
  for (const a of keys) {
    for (const b of keys) {
      if (a === b) continue;
      const m = missing(v[a], v[b]);
      summary.push(`${a}>${b}:${m.length}`);
      rep.push(`## In ${a}, not found in ${b} (${m.length} lines)`, "", ...m.map((l) => `- ${l.slice(0, 300)}`), "");
    }
  }
  fs.writeFileSync(path.join(outdir, `${name}.md`), rep.join("\n"), "utf8");
  console.log(`${name.padEnd(38)} ${keys.join(",").padEnd(30)} ${summary.join("  ")}`);
}
