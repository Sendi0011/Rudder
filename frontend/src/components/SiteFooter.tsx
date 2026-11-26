import Link from "next/link";

const links = [
  { href: "/deposits/", label: "Your deposits" },
  { href: "/for-curators/", label: "For curators" },
  { href: "/contracts/", label: "Contracts" },
  { href: "/docs/", label: "Read the docs" },
];

export default function SiteFooter() {
  return (
    <footer className="site-footer">
      <div className="shell footer-inner">
        <nav aria-label="Footer navigation">
          <ul className="footer-links">
            {links.map((link) => (
              <li key={link.href}>
                <Link href={link.href}>{link.label}</Link>
              </li>
            ))}
          </ul>
        </nav>
        <p className="footer-note">
          Rudder · Uniswap v4 strategy with published limits. No wallet key is
          held by this interface.
        </p>
      </div>
    </footer>
  );
}
