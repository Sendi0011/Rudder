import type { Metadata } from "next";
import "@fontsource/bricolage-grotesque/400.css";
import "@fontsource/bricolage-grotesque/600.css";
import "@fontsource/ibm-plex-sans/400.css";
import "@fontsource/ibm-plex-sans/500.css";
import "@fontsource/ibm-plex-sans/600.css";
import "@fontsource/ibm-plex-sans/700.css";
import "./globals.css";
import SiteHeader from "@/components/SiteHeader";
import SiteFooter from "@/components/SiteFooter";
import Providers from "@/lib/providers";

export const metadata: Metadata = {
  title: {
    default: "Rudder — curated liquidity inside published limits",
    template: "%s · Rudder",
  },
  description:
    "Curators steer an LP range inside on-chain limits. Deposits and exits stay yours; a rebalance outside the limits is rejected.",
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en">
      <body>
        <Providers>
          <a className="sr-only focus:not-sr-only focus:absolute focus:left-4 focus:top-4 focus:z-50 focus:bg-paper focus:px-3 focus:py-2" href="#main">
            Skip to content
          </a>
          <SiteHeader />
          <main id="main" className="shell pb-24">
            {children}
          </main>
          <SiteFooter />
        </Providers>
      </body>
    </html>
  );
}
