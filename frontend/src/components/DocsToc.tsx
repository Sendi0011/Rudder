"use client";

import { useEffect, useState } from "react";

export type DocsTocItem = {
  id: string;
  label: string;
};

export default function DocsToc({ items }: { items: DocsTocItem[] }) {
  const [activeId, setActiveId] = useState(items[0]?.id ?? "");

  useEffect(() => {
    setActiveId(items[0]?.id ?? "");
    const headings = items
      .map((entry) => document.getElementById(entry.id))
      .filter((heading): heading is HTMLElement => Boolean(heading));
    if (!headings.length || typeof IntersectionObserver === "undefined") return;

    const observer = new IntersectionObserver(
      (entries) => {
        const visible = entries
          .filter((entry) => entry.isIntersecting)
          .sort((a, b) => a.boundingClientRect.top - b.boundingClientRect.top);
        const first = visible[0];
        if (first) setActiveId(first.target.id);
      },
      { rootMargin: "-96px 0px -65% 0px", threshold: 0 },
    );

    headings.forEach((heading) => observer.observe(heading));
    return () => observer.disconnect();
  }, [items]);

  return (
    <aside aria-labelledby="toc-heading" className="docs-toc">
      <p id="toc-heading" className="docs-toc-title">
        On this page
      </p>
      {items.length ? (
        <ul className="docs-toc-list">
          {items.map((entry) => (
            <li key={entry.id}>
              <a
                className={`docs-toc-link${entry.id === activeId ? " is-active" : ""}`}
                href={`#${entry.id}`}
                aria-current={entry.id === activeId ? "location" : undefined}
              >
                {entry.label}
              </a>
            </li>
          ))}
        </ul>
      ) : (
        <p className="docs-toc-empty">No sections.</p>
      )}
    </aside>
  );
}
