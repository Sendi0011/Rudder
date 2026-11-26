"use client";

import Link from "next/link";
import CorridorChart from "@/components/CorridorChart";
import LimitsTable, { type LimitUsage } from "@/components/LimitsTable";
import { ChainStatus, EmptyPanel } from "@/components/StatePanels";
import { explorerTx, shortAddress } from "@/lib/chain";
import { useChainData } from "@/lib/chainData";
import { formatCount, formatSigned, formatToken } from "@/lib/format";
import { useVaultDetails } from "@/lib/vaultData";

export default function CuratorDetail({ id }: { id: number }) {
  const { data } = useChainData();
  const curator = data.curators.find((entry) => entry.id === id);
  const vaultDetails = useVaultDetails(curator?.vault);

  if (!curator) {
    return (
      <div className="pt-16">
        <EmptyPanel
          message="That strategy is not registered."
          action={<Link className="button-secondary" href="/vaults/">Back to vaults</Link>}
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
      <Link className="text-sm text-slate underline" href="/vaults/">All vaults</Link>
      <div className="mt-6 flex flex-wrap items-end justify-between gap-8">
        <div>
          <p className="text-sm text-slate">Strategy {curator.id}</p>
          <h1 className="page-title mt-3">Curator {shortAddress(curator.curator)}</h1>
          <p className="mt-3 text-sm text-slate">
            Vault <span className="whitespace-nowrap">{shortAddress(curator.vault)}</span> · range{" "}
            {curator.tickLower} to {curator.tickUpper}
          </p>
        </div>
        <div className="w-44">
          <p className="text-sm text-slate">Return vs holding</p>
          <p className="numeric mt-2 text-3xl">{formatCount(curator.alpha)}</p>
          <p className="mt-2 text-xs text-slate">
            {formatCount(curator.alphaSamples)} checkpoints · dimensionless, not a profit figure
          </p>
        </div>
      </div>

      <div className="mt-10 flex flex-wrap gap-x-6 gap-y-2 text-sm text-slate">
        <ChainStatus {...data} />
        <span>Last rebalance: {last ? `${last.tickLower} to ${last.tickUpper}` : "none recorded"}</span>
        <span>Time-weighted average price tick: {formatCount(twapTick)}</span>
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
            <p className="text-slate">Hold basket · token A</p>
            <p className="numeric mt-1 text-lg">{formatToken(vaultDetails.data?.totalHold0 ?? null)}</p>
          </div>
          <div>
            <p className="text-slate">Hold basket · token B</p>
            <p className="numeric mt-1 text-lg">{formatToken(vaultDetails.data?.totalHold1 ?? null)}</p>
          </div>
          <div>
            <p className="text-slate">Net asset value per share (raw)</p>
            <p className="numeric mt-1 text-lg">{formatCount(vaultDetails.data?.baseNavPerShare ?? null)}</p>
          </div>
          <div>
            <p className="text-slate">Hold value per share (raw)</p>
            <p className="numeric mt-1 text-lg">{formatCount(vaultDetails.data?.baseHoldValuePerShare ?? null)}</p>
          </div>
        </div>
        <Link className="mt-5 inline-block text-sm text-slate underline" href="/docs/mandate/">
          Fee and ranking mandate
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
          <div className="table-wrap mt-5">
            <table>
              <caption>Block is the chain height. Range set is the lower and upper tick written on-chain.</caption>
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
                    <td className="numeric">{formatCount(entry.blockNumber)}</td>
                    <td className="numeric whitespace-nowrap">
                      {formatSigned(entry.tickLower, "ticks")} to {formatSigned(entry.tickUpper, "ticks")}
                    </td>
                    <td className="numeric">{formatCount(entry.tickUpper - entry.tickLower)} ticks</td>
                    <td className="numeric">{formatCount(entry.liquidity)}</td>
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
