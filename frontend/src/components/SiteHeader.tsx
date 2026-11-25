import Link from "next/link";

const links = [
  { href: "/curators/", label: "Curators" },
  { href: "/positions/", label: "My positions" },
  { href: "/console/", label: "Curator console" },
  { href: "/proof/", label: "Live proof" },
  { href: "/evidence/", label: "Evidence" },
  { href: "/protocol/", label: "Protocol" },
  { href: "/docs/", label: "Docs" },
];

export default function SiteHeader() {
  return (
    <header className="shell border-b border-rule pt-5">
      <div className="flex flex-wrap items-end justify-between gap-4">
        <Link href="/" className="group flex items-baseline gap-3 no-underline">
          <svg width="30" height="30" viewBox="0 0 30 30" aria-hidden="true">
            <path d="M3 22.5 15 4l12 18.5" fill="none" stroke="var(--color-ink)" strokeWidth="2" />
            <path d="M7 18.5h16" stroke="var(--color-cobalt)" strokeWidth="3" />
          </svg>
          <span className="font-heading text-[1.6rem] font-semibold leading-none tracking-tight">Rudder</span>
          <span className="hidden text-sm text-slate sm:inline">bounded liquidity, visible limits</span>
        </Link>
        <span className="eyebrow">Unichain Sepolia · chain 1301</span>
      </div>
      <nav aria-label="Main navigation" className="-mx-1 mt-5 flex gap-1 overflow-x-auto pb-3">
        {links.map((link) => (
          <Link
            key={link.href}
            href={link.href}
            className="shrink-0 px-2 py-1 text-sm text-slate no-underline hover:text-ink hover:underline"
          >
            {link.label}
          </Link>
        ))}
      </nav>
    </header>
  );
}
