import Link from "next/link";
import HomeCorridor from "@/components/HomeCorridor";

export default function HomePage() {
  return (
    <div className="pt-12 sm:pt-20">
      <p className="eyebrow">Curated liquidity · Uniswap v4</p>
      <h1 className="page-lead mt-5">
        Curators steer a liquidity range inside published on-chain limits, and every move outside those limits is rejected.
      </h1>
      <div className="mt-12 grid gap-10 border-t border-rule pt-8 lg:grid-cols-[1.6fr_1fr]">
        <HomeCorridor />
        <aside aria-labelledby="try-heading" className="border-l-0 lg:border-l lg:border-rule lg:pl-8">
          <h2 id="try-heading" className="text-xl">
            Try it
          </h2>
          <p className="mt-2 text-slate">Connect a wallet, mint test tokens, deposit and exit.</p>
          <Link className="action mt-5 w-full" href="/try/">
            Open the judge path
          </Link>
          <Link className="mt-4 block text-sm text-slate underline" href="/docs/how-it-works/">
            Read how it works first
          </Link>
        </aside>
      </div>
      <p className="mt-16 border-t border-rule pt-5 text-sm text-slate">
        Evidence: in the local placebo sample the reactive mean was −19.61 bps against a placebo mean of
        −9.39 bps. No curator edge is claimed.{" "}
        <Link href="/evidence/" className="underline">
          See the measurements
        </Link>
        .
      </p>
    </div>
  );
}
