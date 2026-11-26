import Link from "next/link";
import WalletButton from "./WalletButton";

const links = [
  { href: "/vaults/", label: "Vaults" },
  { href: "/try/", label: "Try it" },
  { href: "/proof/", label: "Proof" },
  { href: "/evidence/", label: "Evidence" },
  { href: "/docs/", label: "Docs" },
];

export default function SiteHeader() {
  return (
    <header className="site-header">
      <div className="shell header-inner">
        <Link href="/" className="wordmark">
          Rudder
        </Link>
        <nav aria-label="Main navigation" className="nav">
          {links.map((link) => (
            <Link key={link.href} href={link.href}>
              {link.label}
            </Link>
          ))}
        </nav>
        <div className="header-wallet">
          <WalletButton />
        </div>
      </div>
    </header>
  );
}
