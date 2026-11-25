"use client";

import Link from "next/link";
import CorridorChart from "@/components/CorridorChart";
import LimitsTable, { type LimitUsage } from "@/components/LimitsTable";
import { ChainStatus, EmptyPanel, LoadingPanel } from "@/components/StatePanels";
import { useChainData } from "@/lib/chainData";
import { explorerTx, shortAddress } from "@/lib/chain";
import { formatCount, formatSigned, formatToken } from "@/lib/format";
import { useVaultDetails } from "@/lib/vaultData";

export default function CuratorDetail({ id }: { id: number }) {
  const { data, isLoading } = useChainData();
  const curator = data.curators.find((entry) => entry.id === id);
  const vaultDetails = useVaultDetails(curator?.vault);

  if (isLoading) return <div className="pt-16"><LoadingPanel label="Reading the strategy" /></div>;
  if (!curator) {
    return (
      <div className="pt-16">
        <EmptyPanel
          message="That strategy is not registered."
          action={<Link className="action action-quiet" href="/curators/">Back to curators</Link>}
        />
      </div>
    );
  }

  const history = data.rebalances
    .filter((entry) => entry.vault.toLowerCase() === curator.vault.toLowerCase())
    .sort((a, b) => (a.blockNumber < b.blockNumber ? -1 : 1));
  const last = history.at(-1);
  const previous = history.at(-2);
  const lastCenter = last ? (last.tickLower + last.tickUpper) / 2 : 0;
  const previousCenter = previous ? (previous.tickLower + previous.tickUpper) / 2 : null;
  const twapTick = vaultDetails.data?.twapTick ?? null;

  const usage: LimitUsage = {
    width: last ? last.tickUpper - last.tickLower : null,
    centerShift: previousCenter === null ? null : Math.abs(lastCenter - previousCenter),
    intervalSeconds: previous && last ? last.timestamp - previous.timestamp : null,
    twapDistance: twapTick === null ? null : Math.abs(Math.round(lastCenter) - twapTick),
    priceImpact: null,
    navLoss: null,
    dailyBucketMicroBps: vaultDetails.data?.lossBucket ?? null,
  };

  return (
    <div className="pt-12 sm:pt-16">
      <Link className="text-sm text-slate underline" href="/curators/">All curators</Link>
      <div className="mt-6 flex flex-wrap items-end justify-between gap-8">
        <div>
          <p className="eyebrow">Strategy {curator.id}</p>
          <h1 className="mt-3 text-4xl sm:text-5xl">Curator {shortAddress(curator.curator)}</h1>
          <p className="mt-3 text-sm text-slate">
            Vault <span className="whitespace-nowrap">{shortAddress(curator.vault)}</span> · range{" "}
            {curator.tickLower} to {curator.tickUpper}
          </p>
        </div>
        <div className="min-w-12rem">
          <p className="eyebrow">On-chain alpha vs hold</p>
          <p className="figure mt-2">{formatCount(curator.alpha)}</p>
          <p className="mt-2 text-xs text-slate">
            {formatCount(curator.alphaSamples)} checkpoints · dimensionless, not a profit figure
          </p>
        </div>
      </div>

      <div className="status-strip mt-10">
        <ChainStatus {...data} />
        <span>Last rebalance: {last ? `${last.tickLower} to ${last.tickUpper}` : "none recorded"}</span>
        <span>TWAP tick: {formatCount(twapTick)}</span>
      </div>

      <div className="mt-10 border-y border-rule py-3">
        <CorridorChart data={data} curator={curator} />
      </div>

      <div className="mt-14">
        <LimitsTable envelope={curator.envelope} usage={usage} />
      </div>

      <section className="mt-14 border-t border-rule pt-8" aria-labelledby="performance-heading">
        <h2 id="performance-heading" className="text-2xl">Performance versus holding</h2>
        <p className="mt-2 max-w-2xl text-sm text-slate">
          The hold basket is the benchmark for the performance fee. A fee is zero on a loss or a stale
          oracle, and the benchmark deliberately overstates active skill.
        </p>
        <div className="mt-5 flex flex-wrap gap-x-12 gap-y-4 text-sm">
          <div>
            <p className="eyebrow">Hold basket · token0</p>
            <p className="mt-1 text-lg">{formatToken(vaultDetails.data?.totalHold0 ?? null)}</p>
          </div>
          <div>
            <p className="eyebrow">Hold basket · token1</p>
            <p className="mt-1 text-lg">{formatToken(vaultDetails.data?.totalHold1 ?? null)}</p>
          </div>
          <div>
            <p className="eyebrow">NAV per share (raw)</p>
            <p className="mt-1 text-lg">{formatCount(vaultDetails.data?.baseNavPerShare ?? null)}</p>
          </div>
          <div>
            <p className="eyebrow">Hold value per share (raw)</p>
            <p className="mt-1 text-lg">{formatCount(vaultDetails.data?.baseHoldValuePerShare ?? null)}</p>
          </div>
        </div>
        <Link className="mt-5 inline-block text-sm text-slate underline" href="/docs/mandate/">
          Read the fee and ranking mandate
        </Link>
      </section>

      <section className="mt-14 border-t border-rule pt-8" aria-labelledby="history-heading">
        <div className="flex flex-wrap items-baseline justify-between gap-3">
          <h2 id="history-heading" className="text-2xl">Rebalance history</h2>
          <Link className="text-sm text-slate underline" href="/proof/">Prove a proposed range</Link>
        </div>
        {history.length === 0 ? (
          <EmptyPanel message="No rebalance logs were found for this vault." />
        ) : (
          <div className="table-scroll mt-5">
            <table className="data-table">
              <thead>
                <tr>
                  <th scope="col">Block</th>
                  <th scope="col">Range set</th>
                  <th scope="col">Width used</th>
                  <th scope="col">Liquidity</th>
                  <th scope="col">Transaction</th>
                </tr>
              </thead>
              <tbody>
                {[...history].reverse().map((entry) => (
                  <tr key={entry.txHash}>
                    <td>{formatCount(entry.blockNumber)}</td>
                    <td className="whitespace-nowrap">
                      {formatSigned(entry.tickLower, "ticks")} to {formatSigned(entry.tickUpper, "ticks")}
                    </td>
                    <td>{formatCount(entry.tickUpper - entry.tickLower)} ticks</td>
                    <td>{formatCount(entry.liquidity)}</td>
                    <td>
                      <a className="text-ink underline" href={explorerTx(entry.txHash)} target="_blank" rel="noreferrer">
                        {shortAddress(entry.txHash)}
                      </a>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>
    </div>
  );
}
