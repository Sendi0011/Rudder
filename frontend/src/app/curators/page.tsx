"use client";

import Link from "next/link";
import { ChainStatus, EmptyPanel, ErrorPanel, LoadingPanel } from "@/components/StatePanels";
import { useChainData } from "@/lib/chainData";
import { formatCount } from "@/lib/format";
import { shortAddress } from "@/lib/chain";

export default function CuratorsPage() {
  const { data, isLoading, isError, refetch } = useChainData();
  const ranked = [...data.curators].sort((a, b) =>
    a.alpha === b.alpha ? a.id - b.id : a.alpha > b.alpha ? -1 : 1,
  );
  const tied = ranked.length > 1 && ranked.every((entry) => entry.alpha === ranked[0]?.alpha);

  return (
    <div className="pt-12 sm:pt-16">
      <p className="eyebrow">On-chain ranking</p>
      <div className="mt-4 flex flex-wrap items-end justify-between gap-6">
        <h1 className="page-lead">Curators, ordered by alpha alone.</h1>
        <div className="max-w-sm text-sm text-slate">
          <p>
            The score comes from the registry&apos;s on-chain alpha versus a hold basket. Deposits are
            shown for context and never enter the score.
          </p>
          <Link className="mt-2 inline-block text-ink underline" href="/docs/how-it-works/">
            How ranking works
          </Link>
        </div>
      </div>

      <div className="status-strip mt-10">
        <ChainStatus {...data} />
        <span>Strategies: {formatCount(data.curators.length)}</span>
        <span>Ranked on chain: {formatCount(data.rankedCount)}</span>
        {tied ? <span className="text-slate">All scores tied at zero</span> : null}
      </div>

      {isLoading ? <LoadingPanel /> : null}
      {isError ? <ErrorPanel message="The registry read failed." onRetry={() => void refetch()} /> : null}
      {!isLoading && !isError && ranked.length === 0 ? (
        <EmptyPanel
          message="No strategies are registered yet."
          action={<Link className="action action-quiet" href="/docs/">Read the docs</Link>}
        />
      ) : null}

      {!isLoading && ranked.length > 0 ? (
        <div className="table-scroll mt-6">
          <table className="data-table">
            <thead>
              <tr>
                <th scope="col">Curator</th>
                <th scope="col">Strategy</th>
                <th scope="col">Alpha vs hold</th>
                <th scope="col">Checkpoints</th>
                <th scope="col">Deposits (shares)</th>
                <th scope="col">Live range</th>
                <th scope="col"><span className="sr-only">Open</span></th>
              </tr>
            </thead>
            <tbody>
              {ranked.map((entry) => (
                <tr key={entry.id}>
                  <td className="whitespace-nowrap">{shortAddress(entry.curator)}</td>
                  <td>{entry.id === 0 ? "Narrow envelope" : entry.id === 1 ? "Middle envelope" : `Strategy ${entry.id}`}</td>
                  <td>
                    {formatCount(entry.alpha)}
                    {tied ? <span className="ml-2 text-xs text-slate">tied</span> : null}
                  </td>
                  <td>{formatCount(entry.alphaSamples)}</td>
                  <td className="whitespace-nowrap">{formatCount(entry.shares)}</td>
                  <td className="whitespace-nowrap">
                    {entry.tickLower} to {entry.tickUpper}
                  </td>
                  <td>
                    <Link className="text-ink underline" href={`/curators/${entry.id}/`}>
                      Inspect
                    </Link>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      ) : null}

      <p className="mt-6 max-w-2xl text-sm text-slate">
        Deposits are displayed but never ranked. Alpha is a dimensionless accumulator; it is not a
        profit figure. See the{" "}
        <Link className="underline" href="/docs/mandate/">
          mandate and limits
        </Link>
        .
      </p>
    </div>
  );
}
