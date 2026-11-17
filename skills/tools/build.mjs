// Render data/<name>/manifest.json + data/<name>/sections/*.md into
// skills/<name>/SKILL.md plus reference files.
//
//   bun tools/build.mjs [--root DIR] [--out DIR]
//
// --root: project root holding data/ (default: parent of tools/)
// --out:  directory that receives <name>/ (default: <root>/skills)
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

export const DEFAULT_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");

// ---- canonical JSON (RFC 8785, JCS) for I-JSON data: strings, arrays, objects ----
const LONE_SURROGATE = /[\ud800-\udbff](?![\udc00-\udfff])|(?<![\ud800-\udbff])[\udc00-\udfff]/;

export function canonicalize(v) {
  if (v === null || typeof v === "boolean") return JSON.stringify(v);
  if (typeof v === "string") {
    if (LONE_SURROGATE.test(v)) throw new Error("not I-JSON: lone surrogate in string");
    return JSON.stringify(v); // ECMAScript string escaping is exactly what JCS prescribes
  }
  if (typeof v === "number") {
    if (!Number.isFinite(v)) throw new Error("not I-JSON: non-finite number");
    return JSON.stringify(v); // ECMAScript number serialisation is what JCS prescribes
  }
  if (Array.isArray(v)) return "[" + v.map(canonicalize).join(",") + "]";
  if (typeof v === "object") {
    // default sort compares UTF-16 code units, as JCS requires
    return "{" + Object.keys(v).sort().map((k) => canonicalize(k) + ":" + canonicalize(v[k])).join(",") + "}";
  }
  throw new Error("not JSON: " + typeof v);
}

export const manifestText = (m) => canonicalize(m) + "\n";

// ---- YAML scalar emission for the frontmatter (templated, no YAML library) ----
// Mirrors what PyYAML's safe_dump chose for these values: plain scalar when that is
// unambiguous, single-quoted when plain would be read back as something else.
function yamlScalar(s) {
  if (typeof s !== "string") throw new Error("frontmatter values must be strings");
  const needsDouble = /[\x00-\x08\x0b-\x1f\x7f\u0085\u2028\u2029\ufeff\n\r\t]/.test(s);
  if (needsDouble) return JSON.stringify(s); // JSON strings are valid YAML double-quoted scalars
  const plainOk =
    s !== "" &&
    !/^[-?:,\[\]{}#&*!|>'"%@`\s]/.test(s) &&
    !/\s$/.test(s) &&
    !/: |:$| #/.test(s) &&
    !/^(true|false|yes|no|on|off|y|n|null|~)$/i.test(s) &&
    !/^[-+]?(\.[0-9]+|[0-9][0-9_]*(\.[0-9_]*)?)([eE][-+]?[0-9]+)?$/.test(s) &&
    !/^[-+]?(0x[0-9a-fA-F_]+|0o?[0-7_]+|0b[01_]+|\.(inf|nan)|[0-9]+(:[0-5]?[0-9])+(\.[0-9]*)?)$/i.test(s) &&
    !/^\d{4}-\d\d-\d\d([Tt ].*)?$/.test(s) &&
    !/^(=|<<)$/.test(s);
  return plainOk ? s : "'" + s.replace(/'/g, "''") + "'";
}

// Only the one-line case is needed here; a longer value would be folded by YAML at width 80.
// PyYAML was run with width=10000, so nothing folded below that. Refuse rather than guess.
function fmLine(key, value, indent = "") {
  const t = yamlScalar(value);
  if (t.length + key.length > 9000) throw new Error(`frontmatter value for ${key} too long to emit`);
  return `${indent}${key}: ${t}`;
}

export function render(data, body) {
  const files = {};
  const fm = [
    "---",
    fmLine("name", data.name),
    fmLine("description", data.description),
    "metadata:",
    fmLine("version", String(data.version), "  "),
    fmLine("family", data.family, "  "),
    // Kept byte-identical to the output the YAML-based build produced; see the report.
    fmLine("generated-from", `data/${data.name}/manifest.json`, "  "),
    "---",
  ];
  const out = [...fm, "", "# " + data.title, ""];
  if (data.subtitle) out.push(data.subtitle, "");
  for (const s of data.sections) {
    const text = body(s);
    if (s.place === "core") {
      out.push(text.replace(/\s+$/, ""), "");
      if (s.kind === "lenses-intro") {
        out.push("Each lens has its own reference file. Read a lens file before applying that lens.", "");
      }
    } else if (s.kind === "lens") {
      files[s.place] = text;
      out.push(`- **${s.title}** — ${s.question} Read \`${s.place}\`.`);
    } else {
      files[s.place] = text;
      out.push("", `## ${s.title}`, "", `Read \`${s.place}\` ${s.when}.`, "");
    }
  }
  files["SKILL.md"] = out.join("\n").replace(/\n{3,}/g, "\n\n").replace(/\s+$/, "") + "\n";
  return files;
}

export function loadSkill(root, dirName) {
  const dir = path.join(root, "data", dirName);
  const data = JSON.parse(fs.readFileSync(path.join(dir, "manifest.json"), "utf8"));
  const body = (s) => {
    if (typeof s.body !== "string" || s.body !== path.basename(s.body) || !s.body.endsWith(".md")) {
      throw new Error(`section ${s.id}: body must be a plain .md file name, got ${JSON.stringify(s.body)}`);
    }
    return fs.readFileSync(path.join(dir, "sections", s.body), "utf8");
  };
  return { data, body };
}

export function skillDirs(root) {
  const base = path.join(root, "data");
  if (!fs.existsSync(base)) return [];
  return fs.readdirSync(base, { withFileTypes: true })
    .filter((e) => e.isDirectory() && fs.existsSync(path.join(base, e.name, "manifest.json")))
    .map((e) => e.name).sort();
}

export function build(root, outroot) {
  const built = [];
  for (const dirName of skillDirs(root)) {
    const { data, body } = loadSkill(root, dirName);
    const files = render(data, body);
    const d = path.join(outroot, data.name);
    fs.rmSync(d, { recursive: true, force: true });
    for (const [rel, text] of Object.entries(files)) {
      const p = path.join(d, rel);
      fs.mkdirSync(path.dirname(p), { recursive: true });
      fs.writeFileSync(p, text, "utf8");
    }
    built.push(data.name);
  }
  return built;
}

export function parseArgs(argv, known) {
  const opts = {};
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (!a.startsWith("--") || !known.includes(a.slice(2)) || i + 1 >= argv.length) {
      throw new Error(`usage: [${known.map((k) => "--" + k + " DIR").join("] [")}]`);
    }
    opts[a.slice(2)] = path.resolve(argv[++i]);
  }
  return opts;
}

const isMain = process.argv[1] && fs.realpathSync(process.argv[1]) === fileURLToPath(import.meta.url);
if (isMain) {
  try {
    const o = parseArgs(process.argv.slice(2), ["root", "out"]);
    const root = o.root ?? DEFAULT_ROOT;
    console.log("built:", build(root, o.out ?? path.join(root, "skills")).join(", "));
  } catch (e) {
    console.error("build failed:", e.message);
    process.exitCode = 1;
  }
}
