"use client";

import { isValidElement, useEffect, useRef, useState, type ReactNode } from "react";

function textOf(node: ReactNode): string {
  if (typeof node === "string" || typeof node === "number") return String(node);
  if (Array.isArray(node)) return node.map(textOf).join("");
  if (isValidElement<{ children?: ReactNode }>(node)) return textOf(node.props.children);
  return "";
}

function languageOf(node: ReactNode): string | null {
  if (Array.isArray(node)) {
    for (const child of node) {
      const language = languageOf(child);
      if (language) return language;
    }
    return null;
  }
  if (isValidElement<{ className?: string; children?: ReactNode }>(node)) {
    const match = node.props.className?.match(/language-([^\s]+)/);
    return match?.[1] ?? languageOf(node.props.children);
  }
  return null;
}

export default function CodeBlock({ children }: { children: ReactNode }) {
  const [copied, setCopied] = useState(false);
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);

  useEffect(
    () => () => {
      if (timer.current) clearTimeout(timer.current);
    },
    [],
  );

  async function copy() {
    try {
      await navigator.clipboard.writeText(textOf(children));
      setCopied(true);
      if (timer.current) clearTimeout(timer.current);
      timer.current = setTimeout(() => setCopied(false), 2000);
    } catch {
      setCopied(false);
    }
  }

  return (
    <div className="docs-code">
      <div className="docs-code-bar">
        <span className="docs-code-language">{languageOf(children) ?? "code"}</span>
        <button
          type="button"
          className="docs-copy"
          aria-label={copied ? "Code copied" : "Copy code"}
          onClick={() => void copy()}
        >
          <span aria-live="polite">{copied ? "Copied" : "Copy"}</span>
        </button>
      </div>
      <pre>{children}</pre>
    </div>
  );
}
