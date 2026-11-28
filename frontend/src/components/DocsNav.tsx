"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useEffect, useState } from "react";

type DocsNavItem = {
  slug: string;
  title: string;
  group: string;
};

const groupOrder = ["Start", "Design", "Assurance", "Deployment"];

function hrefFor(slug: string) {
  return slug === "index" ? "/docs/" : `/docs/${slug}/`;
}

export default function DocsNav({
  items,
  activeSlug,
}: {
  items: DocsNavItem[];
  activeSlug: string;
}) {
  const [open, setOpen] = useState(false);
  const pathname = usePathname();

  useEffect(() => {
    setOpen(false);
  }, [pathname]);

  return (
    <nav
      aria-label="Documentation"
      className="docs-nav"
      onKeyDown={(event) => {
        if (event.key === "Escape") setOpen(false);
      }}
    >
      <button
        type="button"
        className="docs-nav-toggle"
        aria-expanded={open}
        aria-controls="docs-nav-list"
        onClick={() => setOpen((value) => !value)}
      >
        <span>Docs menu</span>
        <span className="docs-nav-toggle-state" aria-hidden="true">
          {open ? "Close" : "Open"}
        </span>
      </button>
      <div id="docs-nav-list" className={`docs-nav-list${open ? " is-open" : ""}`}>
        {groupOrder.map((group) => (
          <div className="docs-nav-group" key={group}>
            <p className="docs-nav-group-label">{group}</p>
            <ul className="docs-nav-list-items">
              {items
                .filter((entry) => entry.group === group)
                .map((entry) => (
                  <li key={entry.slug}>
                    <Link
                      className="docs-nav-link"
                      href={hrefFor(entry.slug)}
                      aria-current={entry.slug === activeSlug ? "page" : undefined}
                      onClick={() => setOpen(false)}
                    >
                      {entry.title}
                    </Link>
                  </li>
                ))}
            </ul>
          </div>
        ))}
      </div>
    </nav>
  );
}
