import Link from "next/link";
import { readFileSync } from "node:fs";
import path from "node:path";
import ReactMarkdown, { type Components } from "react-markdown";
import rehypeHighlight from "rehype-highlight";
import remarkGfm from "remark-gfm";
import manifest from "../../content/manifest.json";

type Doc = (typeof manifest)[number];

const groupOrder = ["Start", "Design", "Assurance", "Deployment"];

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

function tocOf(markdown: string) {
  return markdown
    .split("\n")
    .filter((line) => line.startsWith("## "))
    .map((line) => {
      const raw = line.replace(/^##\s+/, "").replace(/\s+<a id="[^"]+".*$/, "").trim();
      return { label: raw, id: slugify(raw) };
    });
}

const components: Components = {
  h2({ children }) {
    return <h2 id={slugify(textOf(children))}>{children}</h2>;
  },
  h3({ children }) {
    return <h3 id={slugify(textOf(children))}>{children}</h3>;
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

  return (
    <div className="grid gap-10 border-t border-rule pt-8 lg:grid-cols-[15rem_minmax(0,1fr)_12rem]">
      <nav aria-label="Documentation" className="text-sm">
        {groupOrder.map((group) => (
          <div key={group} className="mb-6">
            <p className="eyebrow">{group}</p>
            <ul className="mt-2 space-y-1">
              {manifest
                .filter((entry) => entry.group === group)
                .map((entry) => (
                  <li key={entry.slug}>
                    <Link
                      href={entry.slug === "index" ? "/docs/" : `/docs/${entry.slug}/`}
                      className={entry.slug === doc.slug ? "text-ink underline" : "text-slate hover:text-ink"}
                      aria-current={entry.slug === doc.slug ? "page" : undefined}
                    >
                      {entry.title}
                    </Link>
                  </li>
                ))}
            </ul>
          </div>
        ))}
      </nav>
      <article className="docs-prose min-w-0">
        <p className="eyebrow">Docs · {doc.group}</p>
        <ReactMarkdown remarkPlugins={[remarkGfm]} rehypePlugins={[rehypeHighlight]} components={components}>
          {markdown}
        </ReactMarkdown>
      </article>
      <aside aria-labelledby="toc-heading" className="hidden lg:block">
        <p id="toc-heading" className="eyebrow">
          On this page
        </p>
        {toc.length ? (
          <ul className="mt-3 space-y-2 text-sm">
            {toc.map((entry) => (
              <li key={entry.id}>
                <a className="text-slate hover:text-ink" href={`#${entry.id}`}>
                  {entry.label}
                </a>
              </li>
            ))}
          </ul>
        ) : (
          <p className="mt-3 text-sm text-slate">No sections.</p>
        )}
      </aside>
    </div>
  );
}
