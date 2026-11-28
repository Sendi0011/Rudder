import { execFileSync } from "node:child_process";
import { readdirSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, "../..");
const contentDir = path.resolve(here, "../content");

function git(args) {
  return execFileSync("git", args, { cwd: root, encoding: "utf8" }).trim();
}

const commit = git(["rev-parse", "HEAD"]);
const origin = git(["remote", "get-url", "origin"])
  .replace(/^git@github.com:/, "https://github.com/")
  .replace(/\.git$/, "");

const groups = {
  Start: ["index", "how-it-works", "glossary", "demo", "video", "mandate", "claims"],
  Design: ["architecture", "prior-art", "adr/adr-001-architecture", "adr/adr-002-oracle-and-rebalance-swap", "adr/adr-003-protocol-nav-loss-floor", "adr/adr-004-daily-loss-budget"],
  Assurance: ["evidence", "threat-model", "known-limitations", "review-findings", "feedback", "open-questions"],
  Deployment: ["deployments", "changelog"],
};

const sources = new Map();
sources.set("index", { file: "README.md", source: "README.md" });
sources.set("how-it-works", { file: "docs/ARCHITECTURE.md", source: "docs/ARCHITECTURE.md" });
for (const file of readdirSync(path.join(root, "docs"))) {
  if (!file.endsWith(".md")) continue;
  const slug = file.replace(/\.md$/, "").toLowerCase();
  sources.set(slug, { file: `docs/${file}`, source: `docs/${file}` });
}
for (const file of readdirSync(path.join(root, "docs/adr"))) {
  if (!file.endsWith(".md")) continue;
  const slug = `adr/${file.replace(/\.md$/, "").toLowerCase()}`;
  sources.set(slug, { file: `docs/adr/${file}`, source: `docs/adr/${file}` });
}

const glossary = `# Glossary

- **Curator**: the address allowed to change one strategy's range inside the published envelope.
- **Envelope**: the on-chain limits on range width, center shift, TWAP distance, rebalance interval, price impact and NAV loss.
- **TWAP**: time-weighted average price from the pool oracle. The vault compares spot and TWAP before moving liquidity.
- **Rebalance**: a curator's change of the lower and upper tick of a vault's liquidity range.
- **NAV loss**: the measured cost of a rebalance versus holding the previous basket, expressed in basis points.
- **Hold basket**: the token amounts the vault tracks per share so deposits, exits and fees do not dilute other depositors.
- **Alpha**: the curator's measured performance score. It is recorded on-chain and is not a promise of future returns.
- **LP**: a liquidity provider who deposits into a curator vault and keeps ownership of the shares.

This page is part of the rendered frontend docs. It has no separate source file in the repository.
`;

function titleOf(markdown, fallback) {
  const match = markdown.match(/^#\s+(.+)$/m);
  return match?.[1]?.trim() || fallback;
}

function slugifyHeading(value) {
  return value
    .toLowerCase()
    .replace(/[^a-z0-9\s-]/g, "")
    .trim()
    .replace(/\s+/g, "-");
}

function rewrite(markdown, source) {
  let output = markdown.replace(/(!?)\[([^\]]+)\]\(([^)\s]+)(?:\s+"[^"]*")?\)/g, (whole, bang, label, target) => {
    if (/^https?:\/\//.test(target) || target.startsWith("#") || target.startsWith("mailto:")) return whole;
    const clean = target.split("#")[0];
    const hash = target.includes("#") ? `#${target.split("#")[1]}` : "";
    const resolved = path.posix.normalize(path.posix.join(path.posix.dirname(source), clean));
    const slug = resolved.replace(/\.md$/, "").replace(/^docs\//, "").replace(/^README$/, "index").toLowerCase();
    if (sources.has(slug) && clean.endsWith(".md")) {
      return `${bang}[${label}](/docs/${slug}/${hash})`;
    }
    if (clean.endsWith(".md")) {
      return `${bang}[${label}](${origin}/blob/${commit}/${resolved}${hash})`;
    }
    return `${bang}[${label}](${origin}/raw/${commit}/${resolved}${hash})`;
  });

  output = output
    .replace(/<!--\s*claim:RUD-\d+\s*-->/g, "")
    .replace(/claim:RUD-\d+/g, "")
    .replace(/[ \t]+$/gm, "");

  return `${output.trimEnd()}\n\n---\n\nRendered from commit ${commit} · [View source](${origin}/blob/${commit}/${source})\n`;
}

rmSync(contentDir, { recursive: true, force: true });
mkdirSync(contentDir, { recursive: true });

const manifest = [];
for (const [slug, entry] of sources) {
  const markdown = slug === "glossary" ? glossary : readFileSync(path.join(root, entry.file), "utf8");
  const group = Object.entries(groups).find(([, slugs]) => slugs.includes(slug))?.[0] ?? "Start";
  const title = titleOf(markdown, slug);
  const outputPath = path.join(contentDir, `${slug}.md`);
  mkdirSync(path.dirname(outputPath), { recursive: true });
  writeFileSync(outputPath, rewrite(markdown, entry.source));
  manifest.push({ slug, title, group, source: entry.source });
}

writeFileSync(path.join(contentDir, "manifest.json"), `${JSON.stringify(manifest, null, 2)}\n`);
console.log(`rendered ${manifest.length} docs from ${commit.slice(0, 7)}`);
