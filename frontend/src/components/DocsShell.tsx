import Link from "next/link";
import { readFileSync } from "node:fs";
import path from "node:path";
import ReactMarkdown, { type Components } from "react-markdown";
import rehypeHighlight from "rehype-highlight";
import remarkGfm from "remark-gfm";
import CodeBlock from "@/components/CodeBlock";
import DocsNav from "@/components/DocsNav";
import DocsToc, { type DocsTocItem } from "@/components/DocsToc";
import manifest from "../../content/manifest.json";

type Doc = (typeof manifest)[number];

function slugify(value: string) {
  return value
    .toLowerCase()
    .replace(/[^a-z0-9\s-]/g, "")
    .trim()
    .replace(/\s+/g, "-");
}

function textOf(node: React.ReactNode): string {
  if (typeof node === "string" || typeof node === "number") return String(node);
  if (Array.isArray(node)) return node.map(textOf).join("");
  if (node && typeof node === "object" && "props" in node) {
    return textOf((node as { props: { children?: React.ReactNode } }).props.children);
  }
  return "";
}

function tocOf(markdown: string): DocsTocItem[] {
  return markdown
    .split("\n")
    .filter((line) => line.startsWith("## "))
    .map((line) => {
      const raw = line.replace(/^##\s+/, "").replace(/\s+<a id="[^"]+".*$/, "").trim();
      return { label: raw, id: slugify(raw) };
    });
}

function hrefFor(slug: string) {
  return slug === "index" ? "/docs/" : `/docs/${slug}/`;
}

const components: Components = {
  h1({ children }) {
    return <h2>{children}</h2>;
  },
  h2({ children }) {
    const id = slugify(textOf(children));
    return (
      <h2 id={id}>
        {children}
        <a className="docs-anchor" href={`#${id}`} aria-label="Link to this section">
          #
        </a>
      </h2>
    );
  },
  h3({ children }) {
    const id = slugify(textOf(children));
    return (
      <h3 id={id}>
        {children}
        <a className="docs-anchor" href={`#${id}`} aria-label="Link to this section">
          #
        </a>
      </h3>
    );
  },
  a({ href, children }) {
    const target = href ?? "#";
    if (target.startsWith("/docs/")) {
      return <Link href={target}>{children}</Link>;
    }
    if (target.startsWith("http") || target.startsWith("mailto:")) {
      return (
        <a href={target} target="_blank" rel="noreferrer">
          {children}
        </a>
      );
    }
    return <a href={target}>{children}</a>;
  },
  table({ children }) {
    return (
      <div className="docs-table-wrap">
        <table>{children}</table>
      </div>
    );
  },
  pre({ children }) {
    return <CodeBlock>{children}</CodeBlock>;
  },
};

export function docBySlug(slug: string) {
  return manifest.find((entry) => entry.slug === slug);
}

export function staticDocParams() {
  return manifest.filter((entry) => entry.slug !== "index").map((entry) => ({
    slug: entry.slug.split("/"),
  }));
}

export default function DocsShell({ doc }: { doc: Doc }) {
  const markdown = readFileSync(path.join(process.cwd(), "content", `${doc.slug}.md`), "utf8");
  const toc = tocOf(markdown);
  const navItems = manifest.map(({ slug, title, group }) => ({ slug, title, group }));
  const currentIndex = manifest.findIndex((entry) => entry.slug === doc.slug);
  const previous = currentIndex > 0 ? manifest[currentIndex - 1] : undefined;
  const next = currentIndex >= 0 ? manifest[currentIndex + 1] : undefined;

  return (
    <div className="docs-frame">
      <div className="docs-bar">
        <div className="docs-crumbs">
          <Link href="/docs/">Docs</Link>
          <span aria-hidden="true">/</span>
          <span>{doc.group}</span>
        </div>
        <span className="docs-bar-note">Reference</span>
      </div>
      <div className="docs-layout">
        <DocsNav items={navItems} activeSlug={doc.slug} />
        <article className="docs-prose min-w-0">
          <ReactMarkdown remarkPlugins={[remarkGfm]} rehypePlugins={[rehypeHighlight]} components={components}>
            {markdown}
          </ReactMarkdown>
          <div className="docs-pager">
            {previous ? (
              <Link className="docs-pager-link" href={hrefFor(previous.slug)}>
                <span className="docs-pager-label">
                  <span className="docs-pager-arrow" aria-hidden="true">
                    ←
                  </span>
                  Previous
                </span>
                <span className="docs-pager-title">{previous.title}</span>
              </Link>
            ) : (
              <span />
            )}
            {next ? (
              <Link className="docs-pager-link docs-pager-next" href={hrefFor(next.slug)}>
                <span className="docs-pager-label">
                  Next
                  <span className="docs-pager-arrow" aria-hidden="true">
                    →
                  </span>
                </span>
                <span className="docs-pager-title">{next.title}</span>
              </Link>
            ) : (
              <span />
            )}
          </div>
        </article>
        <DocsToc items={toc} />
      </div>
    </div>
  );
}
