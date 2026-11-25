import Link from "next/link";
import DocsNote from "@/components/DocsNote";
import HomeCorridor from "@/components/HomeCorridor";
import TryItPanel from "@/components/TryItPanel";

export default function HomePage() {
  return (
    <div className="pt-12 sm:pt-20">
      <p className="eyebrow">Curated liquidity · Uniswap v4</p>
      <h1 className="page-lead mt-5">
        Curators steer a liquidity range inside published on-chain limits, and every move outside those limits is rejected.
      </h1>
      <div className="mt-12 grid gap-10 border-t border-rule pt-8 lg:grid-cols-[1.6fr_1fr]">
        <HomeCorridor />
        <TryItPanel />
      </div>
      <p className="mt-16 border-t border-rule pt-5 text-sm text-slate">
        Evidence: in the local placebo sample the reactive mean was −19.61 bps against a placebo mean of
        −9.39 bps. No curator edge is claimed.{" "}
        <Link href="/evidence/" className="underline">
          See the measurements
        </Link>
        .
      </p>
      <DocsNote href="/docs/how-it-works/">The corridor, the envelope and the vault flow are described in</DocsNote>
    </div>
  );
}
