"use client";

import { useEffect, useState } from "react";
import { decodeErrorResult } from "viem";
import { usePublicClient } from "wagmi";
import { RudderVaultAbi } from "@/abis";
import { CHAIN_ID, explorerAddress, shortAddress, unichainSepolia } from "@/lib/chain";
import { useChainData } from "@/lib/chainData";
import { formatCount } from "@/lib/format";
import { ChainStatus, EmptyPanel, ErrorPanel, LoadingPanel } from "@/components/StatePanels";

type Outcome = {
  ok: boolean;
  title: string;
  detail: string;
  raw?: string;
};

const reasons: Record<string, string> = {
  RebalanceOutOfBounds: "The range is outside the published envelope.",
  TickNotAligned: "The ticks do not align with the pool spacing.",
  IntervalTooShort: "The rebalance came too soon after the last one.",
  SpotTwapDeviation: "The spot price moved too far from the TWAP.",
  PriceImpactTooHigh: "The price impact is above the published limit.",
  NavLossTooLarge: "The NAV loss is above the published limit.",
  DailyNavLossBudgetExceeded: "The daily NAV loss budget is exhausted.",
  OracleBad: "The oracle data is stale or missing.",
  NotCurator: "Only the assigned curator may rebalance.",
  Paused: "The vault is paused.",
  InvalidRangeWidth: "The range is wider than the published limit.",
  InvalidCenterShift: "The range center moved too far from the TWAP.",
};

function decodeRevert(data?: `0x${string}`) {
  if (!data) return null;
  try {
    const decoded = decodeErrorResult({ abi: RudderVaultAbi, data });
    return { name: decoded.errorName, args: decoded.args };
  } catch {
    return null;
  }
}

export default function ProofPanel() {
  const { data, isLoading, isError, refetch } = useChainData();
  const publicClient = usePublicClient({ chainId: unichainSepolia.id });
  const [id, setId] = useState(0);
  const [lower, setLower] = useState("0");
  const [upper, setUpper] = useState("0");
  const [busy, setBusy] = useState(false);
  const [outcome, setOutcome] = useState<Outcome | null>(null);

  const curator = data.curators.find((entry) => entry.id === id) ?? data.curators[0];
  const twap = data.twap[0]?.tick ?? 0;

  useEffect(() => {
    if (!curator) return;
    const half = curator.envelope.maxTwapDistanceTicks + 200;
    setLower(String(Math.round(twap - half)));
    setUpper(String(Math.round(twap + half)));
    setOutcome(null);
  }, [curator, twap]);

  async function simulate() {
    if (!curator || !publicClient) return;
    setBusy(true);
    setOutcome(null);
    try {
      await publicClient.simulateContract({
        address: curator.vault,
        abi: RudderVaultAbi,
        functionName: "rebalance",
        args: [Number(lower), Number(upper)],
        account: curator.curator,
      });
      setOutcome({
        ok: true,
        title: "Simulation accepted",
        detail: "This call passed the live vault checks. Nothing was signed or broadcast.",
      });
    } catch (error) {
      const cause = error as { data?: `0x${string}`; cause?: { data?: `0x${string}` } };
      const raw = cause.cause?.data ?? cause.data;
      const decoded = decodeRevert(raw);
      setOutcome({
        ok: false,
        title: decoded ? `Rejected by ${decoded.name}` : "Simulation rejected",
        detail: decoded
          ? reasons[decoded.name] ?? "The vault rejected this call."
          : error instanceof Error
            ? error.message
            : "The vault rejected this call.",
        raw,
      });
    } finally {
      setBusy(false);
    }
  }

  return (
    <section>
      <div className="flex flex-wrap items-end justify-between gap-4">
        <div>
          <p className="eyebrow">eth_call · chain {CHAIN_ID}</p>
          <h2 className="mt-2 text-2xl">Live proof</h2>
        </div>
        <ChainStatus {...data} />
      </div>
      <p className="mt-6 max-w-2xl text-slate">
        This page simulates a curator rebalance against the deployed vault. It uses the public RPC and
        the published curator address. No wallet is connected, no key is requested, and no transaction
        is signed or sent.
      </p>
      {isLoading ? <LoadingPanel label="Reading the live vault list" /> : null}
      {isError ? <ErrorPanel message="The live read failed." onRetry={() => void refetch()} /> : null}
      {!curator ? <EmptyPanel message="No strategies are registered." /> : null}
      {curator ? (
        <>
          <div className="mt-10 border-y border-rule py-6">
            <label className="block text-sm">
              Strategy
              <select
                className="mt-2 w-full max-w-md border border-rule bg-paper px-3 py-2"
                value={curator.id}
                onChange={(event) => setId(Number(event.target.value))}
                disabled={busy}
              >
                {data.curators.map((entry) => (
                  <option key={entry.id} value={entry.id}>
                    Strategy {entry.id} · {shortAddress(entry.vault)}
                  </option>
                ))}
              </select>
            </label>
            <div className="mt-6 flex flex-wrap gap-6">
              <label className="text-sm">
                New lower tick
                <input
                  className="mt-2 w-40 border border-rule bg-paper px-3 py-2"
                  type="number"
                  value={lower}
                  onChange={(event) => setLower(event.target.value)}
                  disabled={busy}
                />
              </label>
              <label className="text-sm">
                New upper tick
                <input
                  className="mt-2 w-40 border border-rule bg-paper px-3 py-2"
                  type="number"
                  value={upper}
                  onChange={(event) => setUpper(event.target.value)}
                  disabled={busy}
                />
              </label>
              <div className="flex items-end">
                <button type="button" className="action" disabled={busy} onClick={() => void simulate()}>
                  {busy ? "Simulating…" : "Simulate rebalance"}
                </button>
              </div>
            </div>
          </div>
          <dl className="mt-6 grid gap-3 text-sm sm:grid-cols-2">
            <div>
              <dt className="text-slate">Vault</dt>
              <dd className="break-all">
                <a className="underline" href={explorerAddress(curator.vault)} target="_blank" rel="noreferrer">
                  {curator.vault}
                </a>
              </dd>
            </div>
            <div>
              <dt className="text-slate">Simulated caller</dt>
              <dd className="break-all">{curator.curator}</dd>
            </div>
            <div>
              <dt className="text-slate">TWAP tick</dt>
              <dd>{formatCount(twap)}</dd>
            </div>
            <div>
              <dt className="text-slate">Published TWAP-distance limit</dt>
              <dd>±{formatCount(curator.envelope.maxTwapDistanceTicks)} ticks</dd>
            </div>
          </dl>
          {outcome ? (
            <div
              className={`mt-8 border-l-4 py-4 pl-4 ${outcome.ok ? "border-sea-glass" : "border-signal"}`}
              role="status"
            >
              <p className="font-heading text-lg">{outcome.title}</p>
              <p className="mt-1 text-sm text-slate">{outcome.detail}</p>
              {outcome.raw ? (
                <p className="mt-2 break-all text-xs text-slate">Revert data: {outcome.raw}</p>
              ) : null}
            </div>
          ) : null}
          <p className="mt-8 border-t border-rule pt-4 text-xs text-slate">
            The pre-filled range is deliberately outside the published limit so the live simulation
            demonstrates a rejection. Change the ticks and simulate again to see an accepted call.
          </p>
        </>
      ) : null}
    </section>
  );
}
