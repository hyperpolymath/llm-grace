#!/usr/bin/env bun
// recover-skills.mjs - find lost "skill" texts inside exported AI chat histories.
//
// Usage: bun tools/recover-skills.mjs [--out DIR] [--min-words N] [--name NAME ...] FILE_OR_DIR ...
//
// PRIVACY / SAFETY: this tool runs entirely locally. It imports only node:fs,
// node:path and node:crypto, never opens a network connection, and writes only
// inside the output directory (--out, default "recovered/"). Every write goes
// through writeInside(), which refuses any path that resolves outside that
// directory. Chat exports contain private material: review the output before
// committing or sharing any of it.
//
// Exit status: 0 = ran to completion (including "nothing found"),
//              2 = misuse or an unreadable / invalid input (nothing is written),
//              1 = unexpected failure while writing the output.

import fs from "node:fs";
import path from "node:path";
import { createHash } from "node:crypto";

// ---------------------------------------------------------------- constants

const KNOWN_NAMES = [
  "hermaneut", "tropos", "katamorphe", "seam-architect", "proof-craft",
  "master-detective", "master-negotiator", "sales-expert",
  "director-of-communications", "forensicator", "cyberwar-commander",
  "edge-architect", "mechatronics-systems-engineer",
  "protistology-microbiology-translator", "arthropod-herpetology-specialist",
  "figure-skating-coach", "choreography-architect", "match-my-writing-style",
  "prep-for-meetings", "generate-fresh-ideas", "get-more-perspectives",
  "focus-my-energy",
];

const HEADING_RES = [
  /^SYSTEM IDENTITY\s*(?:&|and)\s*CORE MANDATE\b/i,
  /^Core Mandate\b/i,
  /^Operating Principles\b/i,
  /^Output Architecture\b/i,
  /^Required Output\b/i,
  /^Interaction Protocol\b/i,
  /^SECTION\s+\d+\s*[:.\-–—]/i,
  /^§\s*\d+/,
];

const FEATURES = ["name", "use_when", "instructions", "version", "headings", "role_opener", "frontmatter"];

const USAGE =
  "usage: recover-skills.mjs [--out DIR] [--min-words N] [--name NAME ...] FILE_OR_DIR ...";

// ---------------------------------------------------------------- helpers

const sha256 = (s) => createHash("sha256").update(s).digest("hex");
const normWs = (s) => s.replace(/\s+/g, " ").trim();
const wordCount = (s) => (s.match(/\S+/g) || []).length;
const nameKey = (s) => s.trim().toLowerCase().replace(/[\s_-]+/g, "-");
const escRe = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");

function slugify(s) {
  const slug = String(s).toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "").slice(0, 60).replace(/-+$/g, "");
  return slug || null;
}

const NAMED_ENTITIES = { amp: "&", lt: "<", gt: ">", quot: '"', apos: "'", nbsp: " " };
function decodeEntities(s) {
  if (!s.includes("&")) return s;
  // Single pass, so "&amp;lt;" becomes "&lt;" and not "<".
  return s.replace(/&(?:#[xX]([0-9a-fA-F]{1,6})|#(\d{1,7})|([a-zA-Z]+));/g, (m, hex, dec, name) => {
    if (name !== undefined) return Object.prototype.hasOwnProperty.call(NAMED_ENTITIES, name) ? NAMED_ENTITIES[name] : m;
    const cp = hex !== undefined ? parseInt(hex, 16) : parseInt(dec, 10);
    if (!Number.isFinite(cp) || cp > 0x10ffff || (cp >= 0xd800 && cp <= 0xdfff) || cp === 0) return m;
    return String.fromCodePoint(cp);
  });
}

function parseTime(v) {
  let d = null;
  if (typeof v === "number" && Number.isFinite(v)) {
    d = new Date(v > 1e11 ? v : v * 1000); // Unix seconds (milliseconds tolerated)
  } else if (typeof v === "string") {
    const t = v.trim();
    if (/^\d{9,13}(\.\d+)?$/.test(t)) {
      const n = Number(t);
      d = new Date(n > 1e11 ? n : n * 1000);
    } else if (/^\d{4}-\d{2}-\d{2}/.test(t)) {
      d = new Date(t);
    }
  }
  if (!d || Number.isNaN(d.getTime())) return null;
  const y = d.getUTCFullYear();
  if (y < 1990 || y > 2100) return null;
  return d.toISOString();
}

// ---------------------------------------------------------------- known-name matching

function buildKnown(extraNames) {
  const names = [...new Set([...KNOWN_NAMES, ...extraNames.map(nameKey)])];
  return names.map((n) => ({
    name: n,
    re: new RegExp("(?<![A-Za-z0-9])" + n.split("-").map(escRe).join("[\\s_-]+") + "(?![A-Za-z0-9])", "gi"),
  }));
}

// ---------------------------------------------------------------- scoring

function analyze(text, known) {
  const lines = text.split(/\r?\n/);
  const feats = {};
  const detail = {};

  // known names: positions and counts
  const counts = new Map();
  let firstPos = null; // earliest known-name match within first 300 chars
  for (const k of known) {
    k.re.lastIndex = 0;
    for (const m of text.matchAll(k.re)) {
      counts.set(k.name, (counts.get(k.name) || 0) + 1);
      if (m.index < 300 && (firstPos === null || m.index < firstPos.index)) firstPos = { index: m.index, name: k.name };
    }
  }
  const knownKeys = new Set(known.map((k) => k.name));

  // name: `name: x` line or a bare name on its own line near the top
  let nameLineValue = null;
  let nonEmptySeen = 0;
  for (let i = 0; i < Math.min(lines.length, 40); i++) {
    const raw = lines[i].trim();
    if (!raw) continue;
    nonEmptySeen++;
    const nm = /^(?:[#*>\s-]*)name\s*:\s*[`"']?([A-Za-z0-9][\w .-]{1,80}?)[`"']?\s*$/i.exec(raw);
    if (nm && !feats.name) {
      feats.name = true;
      nameLineValue = nm[1];
      detail.name = "name: line";
      continue;
    }
    const bare = raw.replace(/^[#*`_>\s]+|[*`_\s:]+$/g, "");
    if (!feats.name && bare && raw.length <= 80) {
      if (knownKeys.has(nameKey(bare))) {
        feats.name = true;
        detail.name = "bare name line";
      } else if (nonEmptySeen <= 5 && /^[a-z][a-z0-9]*(?:-[a-z0-9]+)+$/.test(bare)) {
        feats.name = true;
        detail.name = "slug line";
      }
    }
  }

  feats.use_when = /\bUse when\b/i.test(text);
  feats.instructions = lines.some((l) => l.trim() === "Instructions");
  feats.version = /\(v\d+(?:\.\d+)*\)|\bv\d+\.\d+(?:\.\d+)?\b|\bversion:?\s*v?\d+\.\d+(?:\.\d+)?/i.test(text);

  const headingsHit = [];
  for (const l of lines) {
    if (l.length > 160) continue;
    const t = l.trim().replace(/^(?:#{1,6}\s*|[*_`>\s]+)/, "").replace(/^\d+[.)]\s+/, "");
    if (!t || t.length > 120) continue;
    for (const re of HEADING_RES) {
      if (re.test(t)) {
        headingsHit.push(t.slice(0, 40));
        break;
      }
    }
  }
  feats.headings = headingsHit.length > 0;
  if (feats.headings) detail.headings = headingsHit.length;

  feats.role_opener = /(?:^|\n)[ \t>*#_-]*You are (?:the |a |an )?[A-Z][A-Za-z0-9'’-]+/.test(text);

  const fm = /^\s*---[ \t]*\r?\n([\s\S]{0,4000}?)\r?\n---/.exec(text);
  feats.frontmatter = !!(fm && /^name\s*:/m.test(fm[1]) && /^description\s*:/m.test(fm[1]));

  const fired = FEATURES.filter((f) => feats[f]);
  const score = fired.length;
  const knownPresent = counts.size > 0;
  const otherFeatures = score - (feats.name ? 1 : 0);
  const isHit = score >= 3 || (knownPresent && otherFeatures >= 2);
  return { fired, score, detail, counts, firstPos, nameLineValue, isHit, lines };
}

function detectName(text, a) {
  if (a.firstPos) return a.firstPos.name;
  if (a.counts.size) {
    return [...a.counts.entries()].sort((x, y) => y[1] - x[1] || (x[0] < y[0] ? -1 : 1))[0][0];
  }
  if (a.nameLineValue) {
    const s = slugify(a.nameLineValue);
    if (s) return s;
  }
  const md = /^#{1,6}[ \t]+(.+)$/m.exec(text);
  if (md) {
    const s = slugify(md[1].split(/[:–—]| - /)[0]);
    if (s) return s;
  }
  const first = a.lines.find((l) => l.trim());
  if (first && first.trim().length <= 60 && !/[.!?]$/.test(first.trim())) {
    const s = slugify(first.split(/[:–—]| - /)[0]);
    if (s) return s;
  }
  return "unknown-" + sha256(normWs(text)).slice(0, 8);
}

// ---------------------------------------------------------------- metadata from enclosing objects

const isObj = (v) => v !== null && typeof v === "object" && !Array.isArray(v);
const nonEmptyStr = (v) => (typeof v === "string" && v.trim() ? v : null);
const CONTAINER_KEYS = ["conversation", "messages", "mapping", "chat_messages"];
const PLAIN_TYPES = new Set(["text", "message", "input_text", "output_text"]);

function frameRole(f) {
  return nonEmptyStr(f.role) ?? (isObj(f.author) ? nonEmptyStr(f.author.role) : null) ?? nonEmptyStr(f.sender);
}

function extractMeta(frames) {
  const meta = { title: null, time: null, role: null, ref: null };
  // innermost-first fields
  for (let i = frames.length - 1; i >= 0 && !meta.title; i--) meta.title = nonEmptyStr(frames[i].title);
  for (let i = frames.length - 1; i >= 0 && !meta.title; i--) {
    const f = frames[i];
    if (CONTAINER_KEYS.some((k) => k in f)) meta.title = nonEmptyStr(f.name);
  }
  for (let i = frames.length - 1; i >= 0 && !meta.time; i--) {
    const f = frames[i];
    for (const k of ["created_at", "create_time", "timestamp", "updated_at"]) {
      const t = parseTime(f[k]);
      if (t) { meta.time = t; break; }
    }
  }
  let roleIdx = -1;
  for (let i = frames.length - 1; i >= 0; i--) {
    const r = frameRole(frames[i]);
    if (r) { meta.role = r; roleIdx = i; break; }
  }
  if (meta.role) {
    for (let i = frames.length - 1; i > roleIdx; i--) {
      const t = nonEmptyStr(frames[i].type);
      if (t) { if (!PLAIN_TYPES.has(t)) meta.role += "/" + t; break; }
    }
  } else {
    for (let i = frames.length - 1; i >= 0; i--) {
      const t = nonEmptyStr(frames[i].type);
      if (t) { meta.role = t; break; }
    }
  }
  // conversation url / id: outermost enclosing object that has one
  for (const keys of [["url"], ["conversation_id"], ["id", "uuid"]]) {
    for (const f of frames) {
      for (const k of keys) {
        const v = f[k];
        if (nonEmptyStr(v) || (typeof v === "number" && Number.isFinite(v))) { meta.ref = String(v); break; }
      }
      if (meta.ref) break;
    }
    if (meta.ref) break;
  }
  return meta;
}

// ---------------------------------------------------------------- main

function fail(msg, code = 2) {
  process.stderr.write(msg + "\n");
  process.exit(code);
}

function parseArgs(argv) {
  const opts = { out: "recovered", minWords: 300, names: [], inputs: [] };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    const val = (flag) => {
      const eq = a.indexOf("=");
      if (eq > 0 && a.startsWith(flag + "=")) return a.slice(eq + 1);
      if (i + 1 >= argv.length) fail(`error: ${flag} needs a value\n${USAGE}`);
      return argv[++i];
    };
    if (a === "--help" || a === "-h") { console.log(USAGE); process.exit(0); }
    else if (a === "--out" || a.startsWith("--out=")) opts.out = val("--out");
    else if (a === "--min-words" || a.startsWith("--min-words=")) {
      const v = val("--min-words");
      if (!/^\d+$/.test(v) || Number(v) < 1) fail(`error: --min-words must be a positive integer, got "${v}"`);
      opts.minWords = Number(v);
    } else if (a === "--name" || a.startsWith("--name=")) {
      const v = val("--name");
      if (!slugify(v)) fail(`error: --name needs a usable name, got "${v}"`);
      opts.names.push(v);
    } else if (a === "--") { opts.inputs.push(...argv.slice(i + 1)); break; }
    else if (a.startsWith("--")) fail(`error: unknown option ${a}\n${USAGE}`);
    else opts.inputs.push(a);
  }
  if (!opts.out) fail("error: --out must not be empty");
  if (!opts.inputs.length) fail(`error: no input files or directories given\n${USAGE}`);
  return opts;
}

function collectFiles(inputs, outAbs, errors) {
  const files = []; // {display, abs, explicit}
  const seen = new Set();
  const walkDir = (dir, display) => {
    let real;
    try { real = fs.realpathSync(dir); } catch (e) { errors.push(`cannot read directory ${display}: ${e.message}`); return; }
    if (seen.has(real)) return;
    seen.add(real);
    if (real === outAbs) return; // never read our own output back in
    let entries;
    try { entries = fs.readdirSync(dir, { withFileTypes: true }); } catch (e) { errors.push(`cannot read directory ${display}: ${e.message}`); return; }
    entries.sort((a, b) => (a.name < b.name ? -1 : a.name > b.name ? 1 : 0));
    for (const ent of entries) {
      const p = path.join(dir, ent.name);
      const d = display === "." ? ent.name : path.join(display, ent.name);
      let st;
      try { st = fs.statSync(p); } catch { continue; } // dangling symlink etc.
      if (st.isDirectory()) walkDir(p, d);
      else if (st.isFile() && /\.(json|jsonl|ndjson)$/i.test(ent.name)) files.push({ display: d, abs: p, explicit: false });
    }
  };
  for (const input of inputs) {
    let st;
    try { st = fs.statSync(input); } catch (e) { errors.push(`cannot read ${input}: ${e.code === "ENOENT" ? "no such file or directory" : e.message}`); continue; }
    if (st.isDirectory()) walkDir(input, input);
    else if (st.isFile()) files.push({ display: input, abs: input, explicit: true });
    else errors.push(`cannot read ${input}: not a regular file or directory`);
  }
  return files;
}

function main() {
  const opts = parseArgs(process.argv.slice(2));
  const outAbs = path.resolve(opts.out);
  try {
    if (fs.existsSync(outAbs) && !fs.statSync(outAbs).isDirectory()) fail(`error: --out ${opts.out} exists and is not a directory`);
  } catch (e) { fail(`error: cannot inspect --out ${opts.out}: ${e.message}`); }
  const known = buildKnown(opts.names);
  const onlyNames = opts.names.length ? new Set(opts.names.map(nameKey)) : null;

  const errors = [];
  const files = collectFiles(opts.inputs, fs.existsSync(outAbs) ? fs.realpathSync(outAbs) : outAbs, errors);

  const stats = { files: 0, values: 0, skippedLines: 0, candidates: 0, hits: 0, ignoredNoHit: 0 };
  const cache = new Map(); // normalized-hash -> analysis
  const versions = new Map(); // normalized-hash -> version record

  const onString = (raw, frames, jsonPath, file, line) => {
    const text = decodeEntities(raw);
    if (wordCount(text) < opts.minWords) return;
    stats.candidates++;
    const nh = sha256(normWs(text));
    let a = cache.get(nh);
    if (!a) {
      a = analyze(text, known);
      a.name = a.isHit ? detectName(text, a) : null;
      a.lines = null;
      cache.set(nh, a);
    }
    if (!a.isHit) return;
    stats.hits++;
    const meta = extractMeta(frames);
    const loc = { file: file.display, line, path: jsonPath, ...meta };
    let v = versions.get(nh);
    if (!v) {
      v = { nh, text, words: wordCount(text), sha: sha256(text), a, name: a.name, locs: [] };
      versions.set(nh, v);
    }
    v.locs.push(loc);
  };

  const walk = (val, frames, p, file, line) => {
    if (typeof val === "string") {
      if (val.length >= opts.minWords * 2 - 1) onString(val, frames, p, file, line);
    } else if (Array.isArray(val)) {
      for (let i = 0; i < val.length; i++) walk(val[i], frames, `${p}[${i}]`, file, line);
    } else if (isObj(val)) {
      frames.push(val);
      for (const k of Object.keys(val)) walk(val[k], frames, /^[A-Za-z_]\w*$/.test(k) ? `${p}.${k}` : `${p}[${JSON.stringify(k)}]`, file, line);
      frames.pop();
    }
  };

  for (const file of files) {
    let buf;
    try { buf = fs.readFileSync(file.abs, "utf8"); } catch (e) { errors.push(`cannot read ${file.display}: ${e.message}`); continue; }
    if (buf.charCodeAt(0) === 0xfeff) buf = buf.slice(1);
    const isLines = /\.(jsonl|ndjson)$/i.test(file.display);
    if (isLines) {
      stats.files++;
      const ls = buf.split("\n");
      for (let i = 0; i < ls.length; i++) {
        const l = ls[i].trim();
        if (!l) continue;
        let v;
        try { v = JSON.parse(l); } catch { stats.skippedLines++; continue; }
        stats.values++;
        walk(v, [], "$", file, i + 1);
      }
    } else {
      let v;
      try { v = JSON.parse(buf); } catch (e) {
        errors.push(`${file.display}: not valid JSON (${e.message})`);
        continue;
      }
      stats.files++;
      stats.values++;
      walk(v, [], "$", file, null);
    }
  }

  if (errors.length) {
    for (const e of errors) process.stderr.write("error: " + e + "\n");
    process.stderr.write("nothing was written\n");
    process.exit(2);
  }

  // ---- group, rank
  let all = [...versions.values()];
  if (onlyNames) all = all.filter((v) => onlyNames.has(v.name));
  const bySkill = new Map();
  for (const v of all) {
    if (!bySkill.has(v.name)) bySkill.set(v.name, []);
    bySkill.get(v.name).push(v);
  }
  const skillNames = [...bySkill.keys()].sort((a, b) => (a < b ? -1 : a > b ? 1 : 0));
  for (const n of skillNames) {
    const list = bySkill.get(n);
    list.sort((x, y) => y.words - x.words || (x.sha < y.sha ? -1 : 1));
    list.forEach((v, i) => {
      v.rank = i + 1;
      const dated = v.locs.filter((l) => l.time).sort((x, y) => (x.time < y.time ? -1 : x.time > y.time ? 1 : 0));
      v.primary = dated[0] || v.locs[0];
      v.date = v.primary.time ? v.primary.time.slice(0, 10) : "nodate";
      v.fname = `${v.rank}-${v.words}w-${v.date}-${v.sha.slice(0, 12)}.txt`;
    });
    // Containment: a longer version that holds a shorter one in full is usually a wrapper or a quotation of it.
    for (const v of list) v.norm = normWs(v.text);
    for (const v of list) {
      v.contains = list.filter((o) => o !== v && o.norm.length < v.norm.length && v.norm.includes(o.norm)).map((o) => o.rank);
      v.containedIn = list.filter((o) => o !== v && o.norm.length > v.norm.length && o.norm.includes(v.norm)).map((o) => o.rank);
    }
    // Recommended version: highest score; among those, one that reappears whole inside another version; then the longest.
    const top = Math.max(...list.map((v) => v.a.score));
    const best = list.filter((v) => v.a.score === top);
    const core = best.filter((v) => v.containedIn.length > 0);
    const pick = (core.length ? core : best).slice().sort((x, y) => y.words - x.words)[0];
    for (const v of list) {
      const notes = [];
      if (v === pick) notes.push("recommended");
      if (v.contains.length) notes.push("contains rank " + v.contains.join(", ") + " in full");
      v.note = notes.join("; ");
    }
    list.pick = pick;
  }

  const totals = () =>
    [
      `files read: ${stats.files}`,
      `JSON values parsed: ${stats.values}`,
      `lines skipped (unparseable): ${stats.skippedLines}`,
      `candidates considered (strings >= ${opts.minWords} words): ${stats.candidates}`,
      `hits (skill-shaped occurrences): ${stats.hits}`,
      `distinct versions: ${all.length}`,
    ].join("\n");

  if (!all.length) {
    console.log("no skill-shaped text found" + (onlyNames && versions.size ? " (for the names given with --name)" : ""));
    console.log(totals());
    process.exit(0);
  }

  // ---- write (only inside outAbs)
  const writeInside = (rel, data) => {
    const target = path.resolve(outAbs, rel);
    if (target !== outAbs && !target.startsWith(outAbs + path.sep)) throw new Error(`refusing to write outside output directory: ${target}`);
    fs.mkdirSync(path.dirname(target), { recursive: true });
    fs.writeFileSync(target, data);
  };
  try {
    fs.mkdirSync(outAbs, { recursive: true });
    for (const n of skillNames) {
      const dir = path.join(outAbs, n);
      if (fs.existsSync(dir)) {
        // remove stale versions written by an earlier run (our own file-name pattern only)
        for (const f of fs.readdirSync(dir)) if (/^\d+-\d+w-(?:\d{4}-\d{2}-\d{2}|nodate)-[0-9a-f]{12}\.txt$/.test(f)) fs.unlinkSync(path.join(dir, f));
      }
      for (const v of bySkill.get(n)) writeInside(path.join(n, v.fname), v.text);
    }
    const cell = (s, max = 80) => {
      let t = String(s ?? "-").replace(/\s+/g, " ").trim() || "-";
      if (t.length > max) t = t.slice(0, max - 1) + "…";
      return t.replace(/\|/g, "\\|");
    };
    const rows = [];
    for (const n of skillNames) {
      for (const v of bySkill.get(n)) {
        const roles = [...new Set(v.locs.map((l) => l.role).filter(Boolean))];
        rows.push(
          `| ${cell(n)} | ${v.rank} | ${v.words} | ${cell(v.primary.time ?? "null")} | ${cell(roles.join(", ") || "null")} | ${cell(v.primary.title ?? "null")} | ${cell(v.primary.file, 120)} | ${v.a.score} | ${cell(v.a.fired.join(", "))} | ${v.sha.slice(0, 12)} | ${cell(v.note)} |`
        );
      }
    }
    const md = [
      "# Recovered skills",
      "",
      "Generated by tools/recover-skills.mjs. Review before committing: chat exports contain private material.",
      "",
      "| skill | rank | words | date | role | conversation title | source file | score | features | sha256 | note |",
      "| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |",
      ...rows,
      "",
      "## Locations",
      "",
    ];
    for (const n of skillNames) {
      for (const v of bySkill.get(n)) {
        md.push(`### ${n} / ${v.fname} (${v.locs.length} location${v.locs.length === 1 ? "" : "s"})`, "");
        for (const l of v.locs) {
          md.push(`- ${l.file}${l.line ? ` line ${l.line}` : ""} \`${l.path}\` - role: ${l.role ?? "null"}; time: ${l.time ?? "null"}; title: ${l.title ?? "null"}; ref: ${l.ref ?? "null"}`);
        }
        md.push("");
      }
    }
    writeInside("INDEX.md", md.join("\n"));
  } catch (e) {
    fail(`error: could not write output: ${e.message}`, 1);
  }

  // ---- report (only after everything is on disk)
  for (const n of skillNames) {
    const list = bySkill.get(n);
    console.log(`${n}: ${list.length} version${list.length === 1 ? "" : "s"}, longest ${list[0].words}w, best score ${Math.max(...list.map((v) => v.a.score))} -> ${path.join(opts.out, n)}/`);
  }
  console.log(totals());
  console.log(`index: ${path.join(opts.out, "INDEX.md")}`);
}

main();
