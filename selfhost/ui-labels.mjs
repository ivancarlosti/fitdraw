#!/usr/bin/env node
/**
 * FitDraw UI label rewrite — replaces upstream product wording in the baked
 * frontend bundle with FitDraw's shorter labels.
 *
 * Usage: node selfhost/ui-labels.mjs <html-root>
 *
 * Runs right after scrub.mjs in the frontend build stage, on the same tree, and
 * is a build gate: a rename that stops matching (upstream key or literal
 * changed) fails the image build instead of silently shipping upstream wording
 * again.
 *
 * Why the bundle and not the DOM: the same string feeds the "More tools" entry,
 * the command palette entry and the tool label, so rewriting it where it is
 * defined covers all of them without a MutationObserver re-patching nodes React
 * re-renders. Both rewrites are idempotent, so re-running on an already
 * rewritten tree matches the FitDraw values and reports the same counts.
 */
import { promises as fs } from "node:fs";
import path from "node:path";

const root = process.argv[2];
if (!root) {
  console.error("usage: ui-labels.mjs <html-root>");
  process.exit(2);
}

/**
 * toolBar.mermaidToExcalidraw feeds the "More tools" menu entry, the command
 * palette entry and the tool's label, and every shipped locale carries its own
 * translation ("Mermaid para Excalidraw", "Mermaid zu Excalidraw", …), so the
 * value is rewritten rather than the English string. Empty translations (which
 * fall back to English) are normalised in the same pass.
 */
const RENAMES = [
  {
    name: "mermaid tool label",
    pattern: /mermaidToExcalidraw:\s*"(?:[^"\\]|\\.)*"/g,
    replacement: 'mermaidToExcalidraw:"Mermaid"',
    leftover: /mermaidToExcalidraw:\s*"(?!Mermaid")/,
  },
  {
    name: "mermaid dialog title",
    // mermaid.title in the en bundle: {title:"Mermaid to Excalidraw",button:"Insert",…},
    // used by the dialog's fallback screen. Anchored on the sibling "Insert"
    // button so a re-run still matches once the value is already "Mermaid".
    pattern: /title:"(?:[^"\\]|\\.)*",button:"Insert"/g,
    replacement: 'title:"Mermaid",button:"Insert"',
    leftover: /Mermaid to Excalidraw/,
  },
];

const files = [];
for (const file of await awaitArray(walk(root))) {
  if (/\.(js|mjs)$/i.test(file)) files.push(file);
}
if (files.length === 0) {
  console.error(`[ui-labels] ERROR: no JavaScript assets under ${root}`);
  process.exit(1);
}

const counts = new Map(RENAMES.map((rule) => [rule.name, 0]));
const touched = [];

for (const file of files) {
  const source = await fs.readFile(file, "utf8");
  let output = source;
  for (const rule of RENAMES) {
    let hits = 0;
    output = output.replace(new RegExp(rule.pattern.source, rule.pattern.flags), () => {
      hits += 1;
      return rule.replacement;
    });
    if (hits > 0) counts.set(rule.name, counts.get(rule.name) + hits);
  }
  if (output !== source) {
    await fs.writeFile(file, output);
    touched.push(path.relative(root, file));
  }
}

// ---- gates: every rename must hit, and nothing upstream may survive --------
const problems = [];
for (const rule of RENAMES) {
  if (counts.get(rule.name) === 0) {
    problems.push(`no match for ${rule.name} — upstream key or wording changed, update ui-labels.mjs`);
  }
}
for (const file of files) {
  const source = await fs.readFile(file, "utf8");
  for (const rule of RENAMES) {
    if (rule.leftover.test(source)) {
      problems.push(`${path.relative(root, file)}: ${rule.name} still carries the upstream value`);
    }
  }
}
if (problems.length > 0) {
  console.error("[ui-labels] ERROR: label rewrite gates failed:");
  for (const problem of [...new Set(problems)].slice(0, 40)) console.error("  -", problem);
  process.exit(1);
}

// ---- report ---------------------------------------------------------------
for (const rule of RENAMES) {
  console.log(`[ui-labels] ${String(counts.get(rule.name)).padStart(5)}  ${rule.name} -> "Mermaid"`);
}
console.log(`[ui-labels] touched ${touched.length} file(s); gates passed (no upstream Mermaid wording left)`);

async function* walk(dir) {
  for (const entry of await fs.readdir(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) yield* walk(full);
    else if (entry.isFile()) yield full;
  }
}

async function awaitArray(iterable) {
  const out = [];
  for await (const item of iterable) out.push(item);
  return out;
}
