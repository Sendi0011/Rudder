"use client";

import Link from "next/link";
import { ChainStatus, EmptyPanel, ErrorPanel } from "@/components/StatePanels";
import { shortAddress } from "@/lib/chain";
import { useChainData } from "@/lib/chainData";
import { formatCount } from "@/lib/format";

export default function CuratorsPage() {
  const { data, isError, refetch } = useChainData();
  const ranked = [...data.curators].sort((a, b) =>
    a.alpha === b.alpha ? a.id - b.id : a.alpha > b.alpha ? -1 : 1,
  );
  const tied = ranked.length > 1 && ranked.every((entry) => entry.alpha === ranked[0]?.alpha);

  return (
    <div className="pt-12 sm:pt-16">
      <h1 className="page-title">Pick a curator.</h1>
      <div className="mt-4 flex flex-wrap items-end justify-between gap-6">
        <p className="page-intro">
          Each vault has a curator and a set of published limits. Rankings compare returns with
          holding the same tokens, and deposits never enter the score.
        </p>
        <Link className="text-sm text-slate underline" href="/docs/how-it-works/">
          How ranking works
        </Link>
      </div>

      <div className="mt-10 flex flex-wrap gap-x-6 gap-y-2 text-sm text-slate">
        <ChainStatus {...data} />
        <span>Strategies: {formatCount(data.curators.length)}</span>
        <span>Ranked on chain: {formatCount(data.rankedCount)}</span>
        {tied ? <span>All scores tied at zero</span> : null}
      </div>

      {isError ? <ErrorPanel message="The registry read failed." onRetry={() => void refetch()} /> : null}
      {ranked.length === 0 ? (
        <EmptyPanel
          message="No strategies are registered yet."
          action={<button className="button-secondary" type="button" onClick={() => void refetch()}>Try again</button>}
        />
      ) : null}

      {ranked.length > 0 ? (
        <div className="table-wrap mt-6">
          <table>
            <caption>Ranked by return versus holding. Shares are shown for context only.</caption>
            <thead>
              <tr>
                <th scope="col">Curator</th>
                <th scope="col">Strategy</th>
                <th scope="col">Return vs holding</th>
                <th scope="col">Checkpoints</th>
                <th scope="col">Deposits (shares)</th>
                <th scope="col">Live range</th>
                <th scope="col"><span className="sr-only">Open</span></th>
              </tr>
            </thead>
            <tbody>
              {ranked.map((entry) => (
                <tr key={entry.id}>
                  <td className="numeric whitespace-nowrap">{shortAddress(entry.curator)}</td>
                  <td>{entry.id === 0 ? "Narrow limits" : entry.id === 1 ? "Middle limits" : `Strategy ${entry.id}`}</td>
                  <td className="numeric">
                    {formatCount(entry.alpha)}
                    {tied ? <span className="ml-2 text-xs text-slate">tied</span> : null}
                  </td>
                  <td className="numeric">{formatCount(entry.alphaSamples)}</td>
                  <td className="numeric whitespace-nowrap">{formatCount(entry.shares)}</td>
                  <td className="numeric whitespace-nowrap">
                    {entry.tickLower} to {entry.tickUpper}
                  </td>
                  <td>
                    <Link className="text-ink underline" href={`/vaults/${entry.id}/`}>
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
        Deposits are displayed but never ranked. Return versus holding is a dimensionless score, not a
        profit figure. See the{" "}
        <Link className="underline" href="/docs/mandate/">
          mandate and limits
        </Link>
        .
      </p>
    </div>
  );
}
