import Link from "next/link";

export default function DocsNote({ href, children }: { href: string; children: React.ReactNode }) {
  return (
    <p className="mt-10 border-t border-rule pt-4 text-sm text-slate">
      {children}{" "}
      <Link className="underline" href={href}>
        Read the docs
      </Link>
      .
    </p>
  );
}
