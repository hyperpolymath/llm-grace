// One-off importer: originals/raw/seam-architect.paste.txt -> data/seam-architect/
//   bun tools/import-seam.mjs <paste.txt> <data/seam-architect>
//
// Writes manifest.json (canonical JCS) and sections/<id>.md.
// Content is carried line by line, never retyped. Only heading markers and
// blank lines around headings are added.
import fs from "node:fs";
import path from "node:path";
import { DEFAULT_ROOT, manifestText } from "./build.mjs";

const PY_WS = "\\t\\n\\v\\f\\r \\x1c-\\x1f\\x85\\xa0\\u1680\\u2000-\\u200a\\u2028\\u2029\\u202f\\u205f\\u3000";
const rstrip = (s) => s.replace(new RegExp(`[${PY_WS}]+$`), "");
const strip = (s) => rstrip(s.replace(new RegExp(`^[${PY_WS}]+`), ""));
const splitlines = (t) => (t === "" ? [] : t.replace(/(\r\n|[\n\r\v\f\x1c-\x1e\x85\u2028\u2029])$/, "").split(/\r\n|[\n\r\v\f\x1c-\x1e\x85\u2028\u2029]/));

const SECTION = /^SECTION (\d+): (.+)$/;
const LENS = /^LENS ([A-H]): (.+)$/;
const SUB_LENS = /^[A-H]\.\d+ /;
const SUB_SEC = /^\d\.\d+ /;

function mark(lines) {
  const out = [];
  for (const l of lines) {
    let h;
    if (SECTION.test(l)) h = "## " + l;
    else if (LENS.test(l)) h = "# " + l;
    else if (SUB_LENS.test(l)) h = "## " + l;
    else if (SUB_SEC.test(l)) h = "### " + l;
    else { out.push(l); continue; }
    if (out.length && out[out.length - 1] !== "") out.push("");
    out.push(h, "");
  }
  return strip(out.join("\n").replace(/\n{3,}/g, "\n\n")) + "\n";
}

const KIND = ["modes", "mandate", "lenses-intro", "workflows", "outputs", "interaction", "templates", "patterns", "glossary", "meta"];
const PLACE = {
  6: ["references/specialized-templates.md", "when the architecture includes an API gateway or BFF, event-driven integration, a shared database, a legacy monolith, or multi-cloud or hybrid seams"],
  7: ["references/pattern-catalog.md", "when naming or recommending an integration pattern"],
  8: ["references/glossary.md", "when a seam term needs defining for the user"],
};

function main() {
  const [srcArg, dstArg] = process.argv.slice(2);
  if (!srcArg || !dstArg || process.argv.length !== 4) throw new Error("usage: import-seam.mjs <paste.txt> <data/seam-architect dir>");
  const src = path.resolve(srcArg), dst = path.resolve(dstArg);
  const source = path.relative(DEFAULT_ROOT, src).split(path.sep).join("/");
  if (source.startsWith("..")) throw new Error(`source must lie inside the repository (${DEFAULT_ROOT})`);

  const raw = splitlines(fs.readFileSync(src, "utf8").replace(/\r\n?/g, "\n")).map(rstrip);
  if (raw[2] !== "Instructions") throw new Error(`expected "Instructions" on line 3, got ${JSON.stringify(raw[2])}`);
  const [description, title, subtitle] = [raw[1], raw[3], raw[4]];
  let end = 0;
  raw.forEach((l, i) => { if (strip(l) && strip(l) !== "See less") end = i + 1; });
  const body = raw.slice(5, end);

  const starts = [];
  body.forEach((l, i) => { if (SECTION.test(l) || LENS.test(l)) starts.push(i); });
  const blocks = starts.map((a, i) => body.slice(a, i + 1 < starts.length ? starts[i + 1] : body.length));

  const sections = [];
  const bodies = {};
  for (const blk of blocks) {
    const head = blk[0];
    let m, s, id;
    if ((m = SECTION.exec(head))) {
      const n = Number(m[1]);
      const [place, when] = PLACE[n] ?? ["core", null];
      id = `section-${n}`;
      s = { id, title: head, kind: KIND[n], place };
      if (when) s.when = when;
    } else {
      m = LENS.exec(head);
      const slug = m[2].split("(")[0].toLowerCase().replace(/'/g, "").replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "");
      const q = blk.find((l) => l.startsWith("Question:"));
      if (q === undefined) throw new Error(`no Question: line in ${head}`);
      id = `lens-${m[1].toLowerCase()}`;
      s = { id, title: head, kind: "lens", place: `references/lens-${m[1].toLowerCase()}-${slug}.md`, question: q };
    }
    s.body = `${id}.md`;
    bodies[s.body] = mark(blk);
    sections.push(s);
  }

  const manifest = { name: "seam-architect", family: "seam", version: "2.0", title, subtitle, description, source, sections };
  fs.mkdirSync(path.join(dst, "sections"), { recursive: true });
  for (const [f, text] of Object.entries(bodies)) fs.writeFileSync(path.join(dst, "sections", f), text, "utf8");
  fs.writeFileSync(path.join(dst, "manifest.json"), manifestText(manifest), "utf8");
  console.log(`wrote ${dst} with ${sections.length} sections`);
}

try { main(); } catch (e) { console.error("import failed:", e.message); process.exitCode = 1; }
