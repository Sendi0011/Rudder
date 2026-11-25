"use client";

import Link from "next/link";
import CorridorChart from "@/components/CorridorChart";
import { ChainStatus, EmptyPanel, ErrorPanel, LoadingPanel } from "@/components/StatePanels";
import { useChainData } from "@/lib/chainData";
import { shortAddress } from "@/lib/chain";
import { formatCount } from "@/lib/format";

export default function HomeCorridor() {
  const { data, isLoading, isError, refetch } = useChainData();
  const top = [...data.curators].sort((a, b) =>
    a.alpha === b.alpha ? a.id - b.id : a.alpha > b.alpha ? -1 : 1,
  )[0];

  return (
    <section aria-labelledby="corridor-heading">
      <div className="flex flex-wrap items-end justify-between gap-4">
        <div>
          <p className="eyebrow">Top on-chain alpha · Unichain Sepolia</p>
          <h2 id="corridor-heading" className="mt-2 text-2xl">
            {top ? `Curator ${shortAddress(top.curator)}` : "No corridor yet"}
          </h2>
        </div>
        <ChainStatus {...data} />
      </div>
      {isLoading ? <LoadingPanel label="Reading the corridor" /> : null}
      {isError ? <ErrorPanel message="The corridor read failed." onRetry={() => void refetch()} /> : null}
      {!isLoading && !top ? (
        <EmptyPanel message="No strategies are registered yet." />
      ) : null}
      {top ? (
        <>
          <div className="mt-6 border-y border-rule py-3">
            <CorridorChart data={data} curator={top} />
          </div>
          <div className="mt-4 flex flex-wrap items-center justify-between gap-4 text-sm">
            <span className="text-slate">
              Alpha {formatCount(top.alpha)} · range {top.tickLower} to {top.tickUpper} · limits ±
              {formatCount(top.envelope.maxTwapDistanceTicks)} ticks from the TWAP
            </span>
            <Link className="text-ink underline" href={`/curators/${top.id}/`}>
              Open the detail page
            </Link>
          </div>
        </>
      ) : null}
    </section>
  );
}
