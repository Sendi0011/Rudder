import Link from "next/link";
import { formatBps, formatCount, formatSigned } from "@/lib/format";
import type { Envelope } from "@/lib/types";

export interface LimitUsage {
  width: number | null;
  centerShift: number | null;
  intervalSeconds: number | null;
  twapDistance: number | null;
  priceImpact: number | null;
  navLoss: number | null;
  dailyBucketMicroBps: bigint | null;
}

function Used({ value, limit, suffix = "", note }: { value: number | null; limit: number; suffix?: string; note?: string }) {
  if (value === null) return <span className="text-slate">Not in event logs</span>;
  const share = limit > 0 ? Math.min(100, Math.round((Math.abs(value) / limit) * 100)) : 0;
  return (
    <div>
      <span className="whitespace-nowrap">
        {formatSigned(value, "")}{suffix} · {share}% of bound
      </span>
      <span className="mt-1 block h-1 w-24 bg-rule" aria-hidden="true">
        <span className="block h-1 bg-cobalt" style={{ width: `${share}%` }} />
      </span>
      {note ? <span className="mt-1 block text-xs text-slate">{note}</span> : null}
    </div>
  );
}

export default function LimitsTable({ envelope, usage }: { envelope: Envelope; usage: LimitUsage }) {
  const capacityMicroBps = (BigInt(envelope.maxDailyNavLossBps) * 1_000_000n) / 2n;
  const bucketUsed = usage.dailyBucketMicroBps === null ? null : Number(usage.dailyBucketMicroBps) / 1_000_000;

  return (
    <section aria-labelledby="limits-heading">
      <div className="flex flex-wrap items-baseline justify-between gap-3">
        <h2 id="limits-heading" className="text-2xl">
          Limits and the last move
        </h2>
        <Link href="/docs/mandate/" className="text-sm text-slate underline">
          Mandate and limits
        </Link>
      </div>
      <p className="mt-2 max-w-2xl text-sm text-slate">
        The envelope is stored on-chain in the registry. The used column reads rebalance event logs;
        fields the events do not carry are marked as such.
      </p>
      <div className="table-scroll mt-5">
        <table className="data-table">
          <thead>
            <tr>
              <th scope="col">Bound</th>
              <th scope="col">Published limit</th>
              <th scope="col">Used</th>
            </tr>
          </thead>
          <tbody>
            <tr>
              <th scope="row" className="text-left font-normal text-ink">Range width</th>
              <td>{formatCount(envelope.maxRangeWidth)} ticks</td>
              <td><Used value={usage.width} limit={envelope.maxRangeWidth} suffix=" ticks" /></td>
            </tr>
            <tr>
              <th scope="row" className="text-left font-normal text-ink">Centre shift</th>
              <td>{formatCount(envelope.maxCenterShift)} ticks</td>
              <td><Used value={usage.centerShift} limit={envelope.maxCenterShift} suffix=" ticks" /></td>
            </tr>
            <tr>
              <th scope="row" className="text-left font-normal text-ink">Rebalance interval</th>
              <td>{formatCount(envelope.minRebalanceInterval)} s minimum</td>
              <td><Used value={usage.intervalSeconds} limit={envelope.minRebalanceInterval} suffix=" s" /></td>
            </tr>
            <tr>
              <th scope="row" className="text-left font-normal text-ink">TWAP distance</th>
              <td>{formatCount(envelope.maxTwapDistanceTicks)} ticks</td>
              <td>
                <Used
                  value={usage.twapDistance}
                  limit={envelope.maxTwapDistanceTicks}
                  suffix=" ticks"
                  note="Current distance from the range centre to the TWAP tick"
                />
              </td>
            </tr>
            <tr>
              <th scope="row" className="text-left font-normal text-ink">Price impact</th>
              <td>{formatBps(envelope.maxPriceImpactBps, 0)}</td>
              <td><Used value={usage.priceImpact} limit={envelope.maxPriceImpactBps} suffix=" bps" /></td>
            </tr>
            <tr>
              <th scope="row" className="text-left font-normal text-ink">NAV-loss floor</th>
              <td>{formatBps(envelope.maxNavLossBps, 0)}</td>
              <td><Used value={usage.navLoss} limit={Math.abs(envelope.maxNavLossBps)} suffix=" bps" /></td>
            </tr>
            <tr>
              <th scope="row" className="text-left font-normal text-ink">Daily NAV-loss budget</th>
              <td>{formatBps(envelope.maxDailyNavLossBps, 0)}</td>
              <td>
                {bucketUsed === null ? (
                  <span className="text-slate">Not available offline</span>
                ) : (
                  <span className="whitespace-nowrap">
                    {formatBps(bucketUsed)} of {formatBps(Number(capacityMicroBps) / 1_000_000)} capacity
                  </span>
                )}
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </section>
  );
}
