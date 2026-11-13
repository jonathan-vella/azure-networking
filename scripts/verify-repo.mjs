import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';

const ROOT = process.cwd();
const DOCS_ROOT = path.join(ROOT, 'src', 'content', 'docs');
const BASE_PREFIX = '/azure-networking';
const REPO_TREE_PREFIX = 'https://github.com/jonathan-vella/azure-networking/tree/main/';
const REPO_BLOB_PREFIX = 'https://github.com/jonathan-vella/azure-networking/blob/main/';

const VALID_MERMAID_HEADERS = [
  'flowchart',
  'graph',
  'sequenceDiagram',
  'stateDiagram',
  'stateDiagram-v2',
  'classDiagram',
  'erDiagram',
  'mindmap',
  'timeline',
  'journey',
  'gitGraph',
  'quadrantChart',
  'pie',
  'gantt',
  'C4Context',
  'C4Container',
  'architecture-beta',
  'block-beta',
  'xychart-beta',
];

const STALE_PATTERNS = [
  /DO NOT MERGE/i,
  /open draft PR #1/i,
  /partial consolidation/i,
];

const errors = [];

function fail(msg) {
  errors.push(msg);
}

function existsExactCase(targetPath) {
  const resolved = path.resolve(targetPath);
  const rel = path.relative(ROOT, resolved);
  if (rel.startsWith('..') || path.isAbsolute(rel)) return false;
  if (!rel) return fs.existsSync(ROOT);

  const segments = rel.split(path.sep);
  let cur = ROOT;
  for (const seg of segments) {
    try {
      if (!fs.existsSync(cur) || !fs.statSync(cur).isDirectory()) return false;
    } catch {
      return false;
    }
    const entries = fs.readdirSync(cur);
    if (!entries.includes(seg)) return false;
    cur = path.join(cur, seg);
  }
  return true;
}

function stripCodeFromMarkdown(markdown) {
  return markdown
    .replace(/^(?:```|~~~)[\s\S]*?^(?:```|~~~)/gm, '')
    .replace(/`[^`\r\n]+`/g, '');
}

const MD_LINK_TARGET_RE =
  /!?\[[^\]]*\]\(\s*(?:<([^>\r\n]+)>|((?:[^()\s]|\([^()\s]*\))+))(?:\s+(?:"[^"]*"|'[^']*'))?\s*\)/g;

function extractMarkdownLinkTargets(prose) {
  const out = [];
  const withoutNestedImg = prose.replace(
    /!\[[^\]]*\]\(\s*(?:<[^>\r\n]+>|(?:[^()\s]|\([^()\s]*\))+)(?:\s+(?:"[^"]*"|'[^']*'))?\s*\)/g,
    'badge'
  );
  for (const src of [prose, withoutNestedImg]) {
    for (const m of src.matchAll(MD_LINK_TARGET_RE)) {
      const target = (m[1] ?? m[2] ?? '').trim();
      if (target) out.push(target);
    }
  }
  return out;
}

const IGNORED_WALK_DIRS = new Set([
  'node_modules',
  '.git',
  'dist',
  '.angular',
  '.terraform',
  'bin',
  'obj',
]);

function walkFiles(dir) {
  const out = [];
  if (!fs.existsSync(dir)) return out;
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    if (entry.isDirectory() && IGNORED_WALK_DIRS.has(entry.name)) continue;
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      out.push(...walkFiles(full));
    } else if (entry.isFile()) {
      out.push(full);
    }
  }
  return out;
}

function stripHtmlTags(input) {
  let result = input;
  let previous;
  do {
    previous = result;
    result = result.replace(/<[^>]*>/g, '');
  } while (result !== previous);
  return result.replace(/[<>]/g, '');
}

function slugifyHeading(raw) {
  return stripHtmlTags(
    raw
      .replace(/`([^`]*)`/g, '$1')
      .replace(/\[([^\]]+)\]\([^)]+\)/g, '$1')
      .replace(/[*_~]/g, '')
  )
    .trim()
    .toLowerCase()
    .replace(/[^\p{L}\p{N}\s-]/gu, '')
    .replace(/\s+/g, '-')
    .replace(/-+/g, '-')
    .replace(/^-|-$/g, '');
}

function extractAnchors(markdown) {
  const anchors = new Set();
  const counts = new Map();
  let inFence = false;

  for (const line of markdown.split(/\r?\n/)) {
    if (/^```|^~~~/.test(line.trim())) {
      inFence = !inFence;
      continue;
    }
    if (inFence) continue;

    const explicitId = line.match(/\{#([a-zA-Z0-9_-]+)\}\s*$/);
    if (explicitId) {
      anchors.add(explicitId[1]);
    }

    const m = line.match(/^#{1,6}\s+(.+?)(?:\s*\{#[a-zA-Z0-9_-]+\})?\s*$/);
    if (m) {
      const base = slugifyHeading(m[1]);
      if (!base) continue;
      const seen = counts.get(base) ?? 0;
      counts.set(base, seen + 1);
      anchors.add(seen === 0 ? base : `${base}-${seen}`);
    }
  }

  for (const idMatch of markdown.matchAll(/\bid=["']([a-zA-Z0-9_-]+)["']/g)) {
    anchors.add(idMatch[1]);
  }
  return anchors;
}

// 1. Verify .archive/ARCHIVE_MANIFEST.json and gitignore protection
const manifestPath = path.join(ROOT, '.archive', 'ARCHIVE_MANIFEST.json');
if (!fs.existsSync(manifestPath)) {
  fail('Missing .archive/ARCHIVE_MANIFEST.json');
} else {
  const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
  const validCategories = new Set(['duplicate', 'obsolete', 'not-needed']);
  if (!Array.isArray(manifest.entries) || manifest.entries.length === 0) {
    fail('.archive/ARCHIVE_MANIFEST.json has no entries');
  } else {
    for (const entry of manifest.entries) {
      if (!validCategories.has(entry.category)) {
        fail(`Invalid archive category "${entry.category}" on ${entry.path}`);
      }
      if (!/^[a-f0-9]{64}$/.test(entry.sha256 || '')) {
        fail(`Invalid sha256 on archived entry ${entry.path}`);
      }
      const activePath = path.join(ROOT, entry.path);
      if (fs.existsSync(activePath)) {
        fail(`Archived file still exists in active tree: ${entry.path}`);
      }
    }
  }
}

try {
  const trackedTarballs = execFileSync('git', ['ls-files', '.archive/*.tar.gz'], {
    cwd: ROOT,
    encoding: 'utf8',
  }).trim();
  if (trackedTarballs) {
    fail(`Tarball must remain gitignored, but is tracked in Git: ${trackedTarballs}`);
  }
} catch {
  // Ignore if git check unavailable
}

// 2. Collect all Starlight docs routes & anchors
const docFiles = walkFiles(DOCS_ROOT).filter((f) => /\.(md|mdx)$/i.test(f));
if (docFiles.length < 15) {
  fail(`Expected unified handbook chapters under src/content/docs/, found only ${docFiles.length} file(s)`);
}

const routeToFile = new Map();
const routeAnchors = new Map();

for (const file of docFiles) {
  const rel = path.relative(DOCS_ROOT, file).replace(/\\/g, '/');
  const noExt = rel.replace(/\.(md|mdx)$/i, '');
  const slug = noExt === 'index' ? '' : noExt.replace(/\/index$/i, '');
  const route = slug ? `${BASE_PREFIX}/${slug}/` : `${BASE_PREFIX}/`;
  const routeNoSlash = slug ? `${BASE_PREFIX}/${slug}` : BASE_PREFIX;

  const content = fs.readFileSync(file, 'utf8');
  const fmMatch = content.match(/^---\r?\n([\s\S]*?)\r?\n---/);
  if (!fmMatch) {
    fail(`${rel}: missing YAML frontmatter`);
  } else {
    if (!/^title:\s*\S+/m.test(fmMatch[1])) fail(`${rel}: missing frontmatter title`);
    if (!/^description:\s*\S+/m.test(fmMatch[1])) fail(`${rel}: missing frontmatter description`);
  }

  for (const pat of STALE_PATTERNS) {
    if (pat.test(content)) {
      fail(`${rel}: contains stale consolidation text matching ${pat}`);
    }
  }

  const anchors = extractAnchors(content);
  routeToFile.set(route, file);
  routeToFile.set(routeNoSlash, file);
  routeAnchors.set(route, anchors);
  routeAnchors.set(routeNoSlash, anchors);
}

// 3. Validate links, relative images, GitHub repo pointers, and Mermaid blocks in docs
for (const file of docFiles) {
  const rel = path.relative(ROOT, file).replace(/\\/g, '/');
  const content = fs.readFileSync(file, 'utf8');

  // Check Mermaid code blocks
  const mermaidBlocks = [...content.matchAll(/```mermaid[^\r\n]*\r?\n([\s\S]*?)```/g)];
  for (const [, body] of mermaidBlocks) {
    const trimmed = body
      .split(/\r?\n/)
      .map((l) => l.trim())
      .filter((l) => l && !l.startsWith('%%'));
    if (trimmed.length === 0) {
      fail(`${rel}: empty mermaid code block`);
      continue;
    }
    const firstToken = trimmed[0].split(/[\s({[]/)[0];
    if (!VALID_MERMAID_HEADERS.includes(firstToken)) {
      fail(`${rel}: unrecognized Mermaid diagram header "${firstToken}"`);
    }
  }

  // Strip fenced and inline code before scanning Markdown links
  const fmMatch = content.match(/^---\r?\n([\s\S]*?)\r?\n---/);
  const prose = stripCodeFromMarkdown(content);
  const fmText = fmMatch ? fmMatch[1] : '';
  const fmLinkMatches = [...fmText.matchAll(/\b(?:link|href):\s*([^\s\r\n"']+)/g)];
  const jsxHrefMatches = [...prose.matchAll(/\b(?:link|href)=["']([^"']+)["']/g)];

  const rawTargets = new Set([
    ...extractMarkdownLinkTargets(prose),
    ...fmLinkMatches.map((m) => m[1]),
    ...jsxHrefMatches.map((m) => m[1]),
  ]);

  for (const rawTarget of rawTargets) {
    if (
      rawTarget.startsWith('mailto:') ||
      rawTarget.startsWith('tel:') ||
      rawTarget.startsWith('data:')
    ) {
      continue;
    }

    // Check GitHub repo self-links point to real paths
    if (rawTarget.startsWith(REPO_TREE_PREFIX) || rawTarget.startsWith(REPO_BLOB_PREFIX)) {
      const subPath = rawTarget
        .replace(REPO_TREE_PREFIX, '')
        .replace(REPO_BLOB_PREFIX, '')
        .split('#')[0]
        .split('?')[0]
        .replace(/\/$/, '');
      if (subPath && !existsExactCase(path.join(ROOT, subPath))) {
        fail(`${rel}: GitHub repo link points to missing/wrong-case path "${subPath}"`);
      }
      continue;
    }

    if (/^https?:\/\//i.test(rawTarget)) {
      if (/docs\.microsoft\.com/i.test(rawTarget)) {
        fail(`${rel}: legacy docs.microsoft.com link should use learn.microsoft.com (${rawTarget})`);
      }
      continue;
    }

    if (rawTarget.startsWith('#')) {
      const docRel = path.relative(DOCS_ROOT, file).replace(/\\/g, '/').replace(/\.(md|mdx)$/i, '');
      const route = docRel === 'index' ? `${BASE_PREFIX}/` : `${BASE_PREFIX}/${docRel}/`;
      const anchors = routeAnchors.get(route);
      const frag = rawTarget.slice(1);
      if (frag && anchors && !anchors.has(frag)) {
        fail(`${rel}: broken same-page anchor "${rawTarget}"`);
      }
      continue;
    }

    if (rawTarget.startsWith('/')) {
      const [routeWithQuery, frag] = rawTarget.split('#');
      const [routePart] = routeWithQuery.split('?');
      if (!routeToFile.has(routePart)) {
        fail(`${rel}: broken internal route "${rawTarget}"`);
      } else if (frag) {
        const anchors = routeAnchors.get(routePart);
        if (anchors && !anchors.has(frag)) {
          fail(`${rel}: broken cross-page anchor "${rawTarget}"`);
        }
      }
      continue;
    }

    // Relative asset or markdown path
    const [relPart] = rawTarget.split('#')[0].split('?');
    const resolvedTarget = path.resolve(path.dirname(file), relPart);
    if (!existsExactCase(resolvedTarget)) {
      fail(`${rel}: broken or wrong-case relative path "${rawTarget}"`);
    }
  }
}

// 4. Check root README, CONTRIBUTING, THIRD_PARTY_NOTICES for stale consolidation text & local links
for (const rootDoc of ['README.md', 'CONTRIBUTING.md', 'THIRD_PARTY_NOTICES.md']) {
  const full = path.join(ROOT, rootDoc);
  if (!fs.existsSync(full)) {
    fail(`Missing root governance file: ${rootDoc}`);
    continue;
  }
  const text = fs.readFileSync(full, 'utf8');
  for (const pat of STALE_PATTERNS) {
    if (pat.test(text)) {
      fail(`${rootDoc}: contains stale consolidation text matching ${pat}`);
    }
  }
  const prose = stripCodeFromMarkdown(text);
  for (const rawTarget of new Set(extractMarkdownLinkTargets(prose))) {
    if (
      rawTarget.startsWith('#') ||
      rawTarget.startsWith('mailto:') ||
      rawTarget.startsWith('tel:') ||
      rawTarget.startsWith('data:') ||
      /^https?:\/\//i.test(rawTarget)
    ) {
      continue;
    }
    const target = rawTarget.split('#')[0].split('?')[0];
    if (target && !existsExactCase(path.resolve(ROOT, target))) {
      fail(`${rootDoc}: broken or wrong-case link "${target}"`);
    }
  }
}

// 4b. Verify labs/**, samples/**, and tools/** README/INSTALL Markdown docs
const moduleDocSet = new Set();
for (const topDir of ['labs', 'samples', 'tools']) {
  for (const f of walkFiles(path.join(ROOT, topDir))) {
    if (path.basename(f) === 'README.md') {
      moduleDocSet.add(f);
    }
  }
}
const fwInstallDoc = path.join(ROOT, 'tools', 'firewall-monitor', 'INSTALL.md');
if (fs.existsSync(fwInstallDoc)) {
  moduleDocSet.add(fwInstallDoc);
}

for (const mdFile of [...moduleDocSet].sort()) {
  const rel = path.relative(ROOT, mdFile).replace(/\\/g, '/');
  const content = fs.readFileSync(mdFile, 'utf8');

  for (const pat of STALE_PATTERNS) {
    if (pat.test(content)) {
      fail(`${rel}: contains stale consolidation text matching ${pat}`);
    }
  }

  const prose = stripCodeFromMarkdown(content);
  const htmlAttrMatches = [
    ...prose.matchAll(/<(?:img|a)\b[^>]*?\b(?:src|href)=["']([^"']+)["']/gi),
  ];

  const rawTargets = new Set([
    ...extractMarkdownLinkTargets(prose),
    ...htmlAttrMatches.map((m) => m[1].trim()),
  ]);

  for (const rawTarget of rawTargets) {
    if (
      !rawTarget ||
      rawTarget.startsWith('#') ||
      rawTarget.startsWith('mailto:') ||
      rawTarget.startsWith('tel:') ||
      rawTarget.startsWith('data:')
    ) {
      continue;
    }

    if (rawTarget.startsWith(REPO_TREE_PREFIX) || rawTarget.startsWith(REPO_BLOB_PREFIX)) {
      const subPath = rawTarget
        .replace(REPO_TREE_PREFIX, '')
        .replace(REPO_BLOB_PREFIX, '')
        .split('#')[0]
        .split('?')[0]
        .replace(/\/$/, '');
      if (subPath && !existsExactCase(path.join(ROOT, subPath))) {
        fail(`${rel}: GitHub repo link points to missing/wrong-case path "${subPath}"`);
      }
      continue;
    }

    if (/^https?:\/\//i.test(rawTarget)) {
      if (
        (rel.startsWith('labs/') || rel.startsWith('samples/')) &&
        /docs\.microsoft\.com/i.test(rawTarget)
      ) {
        fail(`${rel}: legacy docs.microsoft.com link should use learn.microsoft.com (${rawTarget})`);
      }
      continue;
    }

    const relTarget = rawTarget.split('#')[0].split('?')[0];
    if (!relTarget) continue;
    const resolvedTarget = rawTarget.startsWith('/')
      ? path.join(ROOT, relTarget.replace(/^\/+/, ''))
      : path.resolve(path.dirname(mdFile), relTarget);
    if (!existsExactCase(resolvedTarget)) {
      fail(`${rel}: broken or wrong-case relative path "${rawTarget}"`);
    }
  }
}

// 5. Ensure npm lockfiles only reference public registry.npmjs.org
for (const lockRel of [
  'package-lock.json',
  'tools/netbench/dashboard/api/package-lock.json',
  'tools/netbench/dashboard/web/package-lock.json',
  'tools/firewall-monitor/firewall-mon-app/package-lock.json',
]) {
  const lockFull = path.join(ROOT, lockRel);
  if (fs.existsSync(lockFull)) {
    const lockText = fs.readFileSync(lockFull, 'utf8');
    if (/pkgs\.visualstudio\.com/i.test(lockText)) {
      fail(`${lockRel}: contains private Azure Artifacts feed URL instead of registry.npmjs.org`);
    }
  }
}

// 6. Enforce safe GitHub Actions workflows
const wfDir = path.join(ROOT, '.github', 'workflows');
const allowedWorkflows = new Set(['checks.yml', 'deploy-pages.yml']);
const actualWorkflows = fs.existsSync(wfDir) ? fs.readdirSync(wfDir) : [];
for (const wf of actualWorkflows) {
  if (!allowedWorkflows.has(wf)) {
    fail(`Unapproved workflow in .github/workflows/: ${wf}`);
    continue;
  }
  const wfContent = fs.readFileSync(path.join(wfDir, wf), 'utf8');
  const forbidden = [/\bschedule:/, /azure\/login/i, /\baz deployment\b/i, /\bterraform apply\b/i, /\bterraform destroy\b/i];
  for (const pat of forbidden) {
    if (pat.test(wfContent)) {
      fail(`.github/workflows/${wf}: contains forbidden deployment/schedule pattern ${pat}`);
    }
  }
}

if (errors.length > 0) {
  console.error(`Verification failed with ${errors.length} error(s):`);
  for (const err of errors) {
    console.error(`  - ${err}`);
  }
  process.exit(1);
}

console.log(
  `OK: verified ${docFiles.length} handbook pages, ${moduleDocSet.size} module docs, exact-case assets/links/anchors, Mermaid headers, archive manifest, and safe CI workflows.`
);
