import Link from "next/link";

export default function SiteFooter() {
  return (
    <footer className="border-t border-rule bg-paper/60">
      <div className="shell flex flex-wrap items-start justify-between gap-8 py-10 text-sm">
        <div className="max-w-md">
          <p className="font-heading text-xl">Rudder</p>
          <p className="mt-2 text-slate">
            A hook and vault system for curated Uniswap v4 liquidity. Nothing here is audited, and no
            profit is promised.
          </p>
        </div>
        <div className="flex flex-wrap gap-x-8 gap-y-2">
          <Link className="text-slate hover:text-ink" href="/docs/how-it-works/">
            How it works
          </Link>
          <Link className="text-slate hover:text-ink" href="/docs/glossary/">
            Glossary
          </Link>
          <Link className="text-slate hover:text-ink" href="/docs/mandate/">
            Mandate and limits
          </Link>
          <Link className="text-slate hover:text-ink" href="/docs/claims/">
            Claims
          </Link>
        </div>
      </div>
    </footer>
  );
}
