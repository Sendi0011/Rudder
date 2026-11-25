import type { Metadata } from "next";
import { Bricolage_Grotesque, IBM_Plex_Sans } from "next/font/google";
import "./globals.css";
import SiteHeader from "@/components/SiteHeader";
import SiteFooter from "@/components/SiteFooter";
import Providers from "@/lib/providers";

const display = Bricolage_Grotesque({
  subsets: ["latin"],
  variable: "--font-display",
  display: "swap",
});

const plex = IBM_Plex_Sans({
  subsets: ["latin"],
  weight: ["400", "500", "600", "700"],
  variable: "--font-plex",
  display: "swap",
});

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
    <html lang="en" className={`${display.variable} ${plex.variable}`}>
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
