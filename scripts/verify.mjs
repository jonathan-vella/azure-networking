// Adapted from the MIT-licensed jonathan-vella/azure-vwan-review verifier.
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../docs/virtual-wan/review");
const FILES = [
  "README.md",
  "01-vwan-review-checklist.md",
  "02-vwan-review-addendum.md",
  "03-vwan-waf-cheatsheet.md",
  "04-vwan-architecture-faq.md",
  "prompts/README.md",
  "prompts/00-blueprint.prompt.md",
  "prompts/refresh-sources.prompt.md",
  "prompts/add-or-update-control.prompt.md",
  "prompts/verify-pack.prompt.md",
];
const slug = (heading) => heading.toLowerCase().replace(/[^\w\s-]/g, "").replace(/\s/g, "-");

function stripCode(src) {
  let out = "";
  let inFence = false;
  for (const line of src.split("\n")) {
    if (/^```/.test(line)) {
      inFence = !inFence;
      out += "\n";
      continue;
    }
    if (inFence) {
      out += "\n";
      continue;
    }
    out += line.replace(/`[^`]*`/g, " ") + "\n";
  }
  return out;
}

const anchors = {};
for (const rel of FILES) {
  const abs = path.join(ROOT, rel);
  if (!fs.existsSync(abs)) {
    console.error(`MISSING FILE: ${rel}`);
    process.exit(1);
  }
  const src = fs.readFileSync(abs, "utf8");
  const set = new Set();
  for (const m of src.matchAll(/^#{1,6}\s+(.+?)\s*$/gm)) set.add(slug(m[1]));
  for (const m of src.matchAll(/\bid=["']([^"']+)["']/g)) set.add(m[1]);
  anchors[rel] = set;
}

let bad = 0;
for (const rel of FILES) {
  const src = stripCode(fs.readFileSync(path.join(ROOT, rel), "utf8"));
  const dir = path.dirname(rel);
  for (const m of src.matchAll(/\]\(([^)]+)\)/g)) {
    const target = m[1].trim();
    if (/^(https?:|mailto:|#)/.test(target) || target.startsWith("<")) continue;
    const [file, frag] = target.split("#");
    const resolvedAbs = file ? path.resolve(ROOT, dir, file) : path.join(ROOT, rel);
    const repoRel = path.relative(ROOT, resolvedAbs).split(path.sep).join("/");
    if (!frag) {
      if (!fs.existsSync(resolvedAbs) || repoRel.startsWith("..")) {
        console.error(`MISS-FILE ${rel} -> ${target}`);
        bad++;
      }
      continue;
    }
    const known = anchors[repoRel];
    if (!known || !known.has(frag)) {
      console.error(`MISS-ANCHOR ${rel} -> ${repoRel}#${frag}`);
      bad++;
    }
  }
}
if (bad) {
  console.error(`FAIL: ${bad} broken anchors or missing files.`);
  process.exit(1);
}
console.log(`OK: ${FILES.length} review files, cross-file anchors resolve.`);
