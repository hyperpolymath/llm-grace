# Skills collection — working copy

Rule: nothing under `originals/` is ever edited. Rebuilt skills go in `skills/`.

- `originals/raw/` — full texts as pasted by the owner. The owner's chat comment at the start of line 1 has been removed; nothing else is changed.
- `originals/hermaneut.original.md` — same wording as the raw paste, with headings and tables restored.
- The zip of regenerated summaries that started this work, and the reviewer notes, are kept privately and are not in this directory.
- `skills/` — portable Agent Skills (`<name>/SKILL.md` plus reference files), each validated with `agentskills validate`.

## Recovery status

| Skill | Best version recovered | Words |
|---|---|---|
| seam-architect | full v2.0 | 3,070 |
| hermaneut | full v3.0 | 2,226 |
| master-detective | full v3.0 | 2,032 |
| master-negotiator | full v3.0 | 3,162 |
| sales-expert | full | 5,051 |
| katamorphe | condensed v1.0 (tables lost) | 632 |
| tropos | condensed v1.0 (tables lost; not in the zip) | 674 |
| proof-craft | not recovered | — |

Zip summary only, original not yet recovered: protistology-microbiology-translator, arthropod-herpetology-specialist, figure-skating-coach, choreography-architect, cyberwar-commander, edge-architect, forensicator, mechatronics-systems-engineer, director-of-communications, prep-for-meetings, match-my-writing-style, generate-fresh-ideas, get-more-perspectives, focus-my-energy.

## Skills as data (prototype: seam-architect only)

`data/<name>/` is the source of truth. `skills/<name>/` is generated from it and must not be edited by hand.

- `data/<name>/manifest.json` holds everything except the section bodies: name, family, version, title, subtitle, description, source, and for each section its id, title, kind, place, optional `when`, optional `question`, and the file name of its body. It is I-JSON in canonical JCS form (RFC 8785): sorted keys, no insignificant whitespace, one line, UTF-8, one trailing newline.
- `data/<name>/sections/<id>.md` is one file per section body, exactly the text that ends up in the skill.

The tools are plain ES modules that need only Bun (Node 22 also works) and no installed packages.

```bash
bun tools/build.mjs
```

```bash
bun tools/check.mjs
```

```bash
bun tools/inventory.mjs
```

`check.mjs` fails if the output is not valid Agent Skills format (checked natively), if a required section for the skill's family is missing, if any line of the owner's original is absent from the output, or if `skills/` differs from a fresh render. If the third-party `agentskills` validator is installed at the path named in `tools/check.mjs`, it is also run as an optional cross-check and reported on its own line; when it is absent the check says so and does not fail. `tools/import-seam.mjs <paste.txt> <data/seam-architect>` is the one-off importer that created the data layout from `originals/raw/seam-architect.paste.txt`.

## Recovering skills from chat exports

`tools/recover-skills.mjs` searches exported AI chat histories (`.json`, `.jsonl`, `.ndjson`, files or whole directories) for long messages that look like skill texts: it walks every JSON value generically, scores each string of at least `--min-words` words (default 300) against a list of skill features (a short name, "Use when", an `Instructions` line, a version marker, typical headings, a "You are ..." opener, YAML frontmatter), de-duplicates identical texts and writes every distinct version under `recovered/<name>/`, longest first, together with `recovered/INDEX.md` (skill, rank, words, date, role, conversation title, source file, score, features, hash, and all locations).

```bash
bun tools/recover-skills.mjs --out recovered path/to/exports/ path/to/one-chat.jsonl
```

It runs entirely locally: only Node built-ins are used, it opens no network connection, and it writes nothing outside the `--out` directory. `recovered/` is listed in `.gitignore`. Chat exports contain private material, so review everything in `recovered/` before anything from it is committed or shared.
