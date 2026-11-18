// Checks for every skill defined in data/: format, family rules, no loss, no drift.
//
//   bun tools/check.mjs [--root DIR]
//
// Exit status is 0 only when every check passes.
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { DEFAULT_ROOT, build, loadSkill, manifestText, parseArgs, skillDirs } from "./build.mjs";

const FAMILY_KINDS = { seam: ["modes", "mandate", "lenses-intro", "lens", "workflows", "outputs", "interaction"] };
const SKIP_SOURCE_LINES = new Set(["Instructions", "See less"]);
const ALLOWED_KEYS = new Set(["name", "description", "license", "compatibility", "metadata", "allowed-tools"]);
// Optional third-party cross-check: set AGENTSKILLS_BIN to the `agentskills` executable to enable it.
const AGENTSKILLS = process.env.AGENTSKILLS_BIN || "";

// Python-compatible whitespace, so norm() and splitlines() behave as the old checker did.
const WS = "\\t\\n\\v\\f\\r \\x1c-\\x1f\\x85\\xa0\\u1680\\u2000-\\u200a\\u2028\\u2029\\u202f\\u205f\\u3000";
const strip = (s) => s.replace(new RegExp(`^[${WS}]+|[${WS}]+$`, "g"), "");
const splitWords = (s) => strip(s).split(new RegExp(`[${WS}]+`)).filter(Boolean);
const NL = /\r\n|[\n\r\v\f\x1c-\x1e\x85\u2028\u2029]/;
const splitlines = (t) => (t === "" ? [] : t.replace(new RegExp(`(${NL.source})$`), "").split(NL));
const norm = (line) => strip(line.replace(new RegExp(`^[#*${WS}-]+`), "").replace(new RegExp(`[${WS}]+`, "g"), " "));

function walk(dir, rel = "") {
  const out = [];
  for (const e of fs.readdirSync(path.join(dir, rel), { withFileTypes: true })) {
    const r = rel ? rel + "/" + e.name : e.name;
    if (e.isDirectory()) out.push(...walk(dir, r));
    else out.push(r);
  }
  return out.sort((a, b) => (a < b ? -1 : a > b ? 1 : 0));
}

function treeDiff(fresh, actual) {
  if (!fs.existsSync(actual)) return [`${actual} does not exist`];
  const a = new Set(walk(fresh)), b = new Set(walk(actual));
  const diff = [];
  for (const f of a) {
    if (!b.has(f)) diff.push(`missing: ${f}`);
    else if (!fs.readFileSync(path.join(fresh, f)).equals(fs.readFileSync(path.join(actual, f)))) diff.push(`differs: ${f}`);
  }
  for (const f of b) if (!a.has(f)) diff.push(`unexpected: ${f}`);
  return diff;
}

// ---- native Agent Skills format rules ----
function scalar(raw) {
  const t = strip(raw);
  if (t.startsWith("'")) {
    if (!t.endsWith("'") || t.length < 2) return { error: "unterminated single-quoted string" };
    return { value: t.slice(1, -1).replace(/''/g, "'") };
  }
  if (t.startsWith('"')) {
    try { const v = JSON.parse(t); return typeof v === "string" ? { value: v } : { error: "bad quoted string" }; }
    catch { return { error: "unsupported double-quoted string" }; }
  }
  // plain scalar: anything YAML would resolve to a non-string is not a string
  if (t === "" || /^(~|null|true|false|yes|no|on|off)$/i.test(t) || /^[-+]?(\.[0-9]+|[0-9][0-9_]*(\.[0-9_]*)?)([eE][-+]?[0-9]+)?$/.test(t)
      || /^[-+]?(0x[0-9a-fA-F_]+|0o?[0-7_]+|0b[01_]+|\.(inf|nan))$/i.test(t) || /^\d{4}-\d\d-\d\d/.test(t)) {
    return { value: t, nonString: true };
  }
  return { value: t };
}

export function formatProblems(skillMd, dirName) {
  const problems = [];
  const lines = skillMd.split("\n");
  if (lines[0] !== "---") return ["SKILL.md must start with a '---' frontmatter delimiter"];
  const close = lines.indexOf("---", 1);
  if (close < 0) return ["frontmatter is not closed by a '---' line"];
  const fm = lines.slice(1, close);
  const top = {};      // key -> {raw, cont:[], meta:{}}
  let cur = null;
  for (const l of fm) {
    if (l.trim() === "" || l.trim().startsWith("#")) continue;
    if (!/^\s/.test(l)) {
      const m = /^([^:\s][^:]*):(?:\s+(.*))?$/.exec(l);
      if (!m) { problems.push(`frontmatter line is not 'key: value': ${JSON.stringify(l)}`); cur = null; continue; }
      if (m[1] in top) problems.push(`duplicate frontmatter key '${m[1]}'`);
      cur = top[m[1]] = { raw: m[2] ?? "", cont: [], meta: {}, order: 0 };
    } else if (cur) {
      const m = /^\s+([^:\s][^:]*):(?:\s+(.*))?$/.exec(l);
      if (m) cur.meta[m[1]] = m[2] ?? "";
      else cur.cont.push(l.trim());
    }
  }
  for (const k of Object.keys(top)) {
    if (!ALLOWED_KEYS.has(k)) problems.push(`unexpected frontmatter key '${k}' (allowed: ${[...ALLOWED_KEYS].join(", ")})`);
  }
  // name
  if (!top.name) problems.push("missing required field 'name'");
  else {
    const r = scalar(top.name.raw);
    const name = r.error || r.nonString ? null : r.value;
    if (name === null) problems.push(`name is not a string${r.error ? ": " + r.error : ""}`);
    else {
      const len = [...name].length;
      if (len < 1 || len > 64) problems.push(`name is ${len} characters (must be 1-64)`);
      if (!/^[\p{Ll}\p{Nd}]+(-[\p{Ll}\p{Nd}]+)*$/u.test(name)) {
        problems.push(`name ${JSON.stringify(name)} must be lowercase letters, digits and single hyphens, not starting or ending with a hyphen`);
      }
      if (name !== dirName) problems.push(`name ${JSON.stringify(name)} does not equal the directory name ${JSON.stringify(dirName)}`);
    }
  }
  // description
  if (!top.description) problems.push("missing required field 'description'");
  else {
    const r = scalar([top.description.raw, ...top.description.cont].join(" "));
    if (r.error || r.nonString) problems.push(`description is not a string${r.error ? ": " + r.error : ""}`);
    else {
      const len = [...r.value].length;
      if (len === 0) problems.push("description is empty");
      if (len > 1024) problems.push(`description is ${len} characters (limit 1024)`);
    }
  }
  // metadata: flat map of string -> string
  if (top.metadata) {
    const md = top.metadata;
    if (md.raw !== "" || md.cont.length) problems.push("metadata must be a map of string keys to string values");
    for (const [k, v] of Object.entries(md.meta)) {
      const r = scalar(v);
      if (r.error || r.nonString || v.trim() === "") problems.push(`metadata.${k} is not a string value (${JSON.stringify(v)}); quote it`);
    }
  }
  return problems;
}

function crossCheck(dir) {
  // Optional third-party validator. Never counts as a pass unless it actually ran and exited 0.
  try { fs.accessSync(AGENTSKILLS, fs.constants.X_OK); }
  catch { return { line: "agentskills cross-check: NOT AVAILABLE (not run)", problem: null }; }
  const r = spawnSync(AGENTSKILLS, ["validate", dir], { encoding: "utf8" });
  if (r.error) return { line: `agentskills cross-check: COULD NOT RUN (${r.error.message})`, problem: `agentskills could not run: ${r.error.message}` };
  if (r.status === null) return { line: `agentskills cross-check: KILLED by signal ${r.signal}`, problem: `agentskills killed by ${r.signal}` };
  const text = ((r.stdout ?? "") + (r.stderr ?? "")).trim();
  if (r.status !== 0) return { line: `agentskills cross-check: FAIL (exit ${r.status}) ${text}`, problem: `agentskills validate exit ${r.status}: ${text}` };
  return { line: `agentskills cross-check: ran, exit 0${text ? " - " + text : ""}`, problem: null };
}

function checkSkill(root, dirName) {
  const problems = [];
  let loaded;
  try { loaded = loadSkill(root, dirName); } catch (e) { return [`data/${dirName}: cannot load: ${e.message}`]; }
  const { data, body } = loaded;
  const name = data.name;
  const d = path.join(root, "skills", name);

  // 0. manifest must be canonical JCS (one line, sorted keys, trailing newline)
  const mpath = path.join(root, "data", dirName, "manifest.json");
  let canonical;
  try { canonical = manifestText(data); } catch (e) { problems.push(`manifest.json is not I-JSON: ${e.message}`); }
  if (canonical !== undefined && canonical !== fs.readFileSync(mpath, "utf8")) problems.push("manifest.json is not in canonical JCS form (RFC 8785) with one trailing newline");

  // 1. drift: committed output must equal a fresh render
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "skills-check-"));
  try {
    build(root, tmp);
    const diff = treeDiff(path.join(tmp, name), d);
    if (diff.length) problems.push(`skills/${name} differs from a fresh render: ${JSON.stringify(diff)}`);
  } catch (e) {
    problems.push(`fresh render failed: ${e.message}`);
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
  }
  if (!fs.existsSync(path.join(d, "SKILL.md"))) { problems.push(`skills/${name}/SKILL.md does not exist`); return problems; }

  // 2. format rules, natively; third-party validator as optional cross-check
  const skill = fs.readFileSync(path.join(d, "SKILL.md"), "utf8");
  for (const p of formatProblems(skill, path.basename(d))) problems.push("format: " + p);
  const x = crossCheck(d);
  console.log("  " + x.line);
  if (x.problem) problems.push(x.problem);

  // 3. family rules
  const kinds = new Set(data.sections.map((s) => s.kind));
  const required = FAMILY_KINDS[data.family];
  if (!required) problems.push(`unknown family '${data.family}'`);
  else {
    const missing = required.filter((k) => !kinds.has(k)).sort((a, b) => (a < b ? -1 : a > b ? 1 : 0));
    if (missing.length) problems.push(`family '${data.family}' requires sections: ${JSON.stringify(missing)}`);
  }
  if (!data.description.toLowerCase().includes("use when")) problems.push("description has no 'Use when' trigger");
  const mdFiles = walk(d).filter((f) => f.endsWith(".md"));
  const refs = mdFiles.filter((f) => f !== "SKILL.md");
  for (const ref of refs) if (!skill.includes("`" + ref + "`")) problems.push(`${ref} is never mentioned in SKILL.md`);
  const nlines = skill.split("\n").length - 1;
  if (nlines > 500) problems.push(`SKILL.md is ${nlines} lines (limit 500)`);

  // 4. no loss: every line of the owner's original appears in the output
  let lost = [], nsrc = 0;
  if (data.source) {
    const have = new Set();
    for (const f of mdFiles) for (const l of splitlines(fs.readFileSync(path.join(d, f), "utf8"))) have.add(norm(l));
    have.add(norm(data.description));
    const srcPath = path.join(root, data.source);
    if (!fs.existsSync(srcPath)) problems.push(`source ${data.source} does not exist`);
    else {
      const src = splitlines(fs.readFileSync(srcPath, "utf8")).slice(1); // line 1 is the owner's comment
      const counted = src.filter((l) => norm(l) && !SKIP_SOURCE_LINES.has(strip(l)));
      nsrc = counted.length;
      lost = counted.filter((l) => !have.has(norm(l)));
      if (lost.length) problems.push(`${lost.length} original lines missing, e.g. ${JSON.stringify(lost.slice(0, 3))}`);
    }
  }
  const words = Object.fromEntries(mdFiles.map((f) => [f, splitWords(fs.readFileSync(path.join(d, f), "utf8")).length]));
  const refWords = Object.entries(words).filter(([k]) => k !== "SKILL.md").reduce((a, [, v]) => a + v, 0);
  console.log(`${name}: SKILL.md ${nlines} lines / ${words["SKILL.md"]} words; ${refs.length} reference files / ${refWords} words`
    + (data.source ? `; original lines kept ${nsrc - lost.length}/${nsrc}` : ""));
  return problems;
}

function main() {
  const o = parseArgs(process.argv.slice(2), ["root"]);
  const root = o.root ?? DEFAULT_ROOT;
  let failed = false;
  const dirs = skillDirs(root);
  if (dirs.length === 0) { console.log("  FAIL: no skills found under data/"); failed = true; }
  for (const dirName of dirs) {
    for (const p of checkSkill(root, dirName)) { failed = true; console.log("  FAIL:", p); }
  }
  console.log("RESULT:", failed ? "FAIL" : "PASS");
  process.exitCode = failed ? 1 : 0;
}

const isMain = process.argv[1] && fs.realpathSync(process.argv[1]) === fileURLToPath(import.meta.url);
if (isMain) {
  try { main(); } catch (e) { console.log("  FAIL: unexpected error:", e.message); console.log("RESULT: FAIL"); process.exitCode = 1; }
}
