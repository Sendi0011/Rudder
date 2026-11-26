"use client";

import Link from "next/link";
import { useState } from "react";
import { useAccount, usePublicClient, useReadContract, useSwitchChain, useWriteContract } from "wagmi";
import { RudderVaultAbi } from "@/abis";
import { explorerTx, shortAddress, unichainSepolia } from "@/lib/chain";
import { ChainStatus, EmptyPanel, ErrorPanel } from "@/components/StatePanels";
import { useChainData } from "@/lib/chainData";
import { formatCount } from "@/lib/format";
import type { Curator, Envelope } from "@/lib/types";

type Notice = { kind: "ok" | "error"; text: string; hash?: string };

function preflight(lower: number, upper: number, twap: number, envelope: Envelope, last: number) {
  const reasons: string[] = [];
  const now = Math.floor(Date.now() / 1000);
  if (!Number.isFinite(lower) || !Number.isFinite(upper) || lower >= upper) {
    reasons.push("Lower tick must be below upper tick.");
    return reasons;
  }
  const width = upper - lower;
  const center = (lower + upper) / 2;
  if (width > envelope.maxRangeWidth) reasons.push(`Range width exceeds ${envelope.maxRangeWidth} ticks.`);
  if (Math.abs(center - twap) > envelope.maxCenterShift) {
    reasons.push(`Range center is more than ${envelope.maxCenterShift} ticks from the average price.`);
  }
  if (Math.abs(lower - twap) > envelope.maxTwapDistanceTicks || Math.abs(upper - twap) > envelope.maxTwapDistanceTicks) {
    reasons.push(`A bound is more than ${envelope.maxTwapDistanceTicks} ticks from the average price.`);
  }
  if (now - last < envelope.minRebalanceInterval) {
    reasons.push(`Wait ${envelope.minRebalanceInterval - (now - last)} more seconds before rebalancing.`);
  }
  return reasons;
}

function ConsoleRow({
  curator,
  twap,
  owner,
  wrongChain,
  oracleReady,
}: {
  curator: Curator;
  twap: number;
  owner?: `0x${string}`;
  wrongChain: boolean;
  oracleReady: boolean;
}) {
  const vault = curator.vault;
  const publicClient = usePublicClient({ chainId: unichainSepolia.id });
  const { writeContractAsync } = useWriteContract();
  const [lower, setLower] = useState(String(curator.tickLower));
  const [upper, setUpper] = useState(String(curator.tickUpper));
  const [busy, setBusy] = useState<string | null>(null);
  const [notice, setNotice] = useState<Notice | null>(null);

  const assigned = useReadContract({
    address: vault,
    abi: RudderVaultAbi,
    functionName: "curator",
  });
  const last = useReadContract({
    address: vault,
    abi: RudderVaultAbi,
    functionName: "lastRebalanceTimestamp",
  });
  const liquidity = useReadContract({
    address: vault,
    abi: RudderVaultAbi,
    functionName: "positionLiquidity",
  });
  const isCurator = Boolean(owner && assigned.data && owner.toLowerCase() === assigned.data.toLowerCase());
  const reasons = preflight(
    Number(lower),
    Number(upper),
    twap,
    curator.envelope,
    last.data !== undefined ? Number(last.data) : 0,
  );
  const canRebalance = isCurator && !wrongChain && oracleReady && reasons.length === 0;

  async function rebalance() {
    setNotice(null);
    if (!publicClient || !canRebalance) return;
    setBusy("Rebalance");
    try {
      const hash = await writeContractAsync({
        address: vault,
        abi: RudderVaultAbi,
        functionName: "rebalance",
        args: [Number(lower), Number(upper)],
      });
      await publicClient.waitForTransactionReceipt({ hash });
      setNotice({ kind: "ok", text: "Rebalance confirmed.", hash });
    } catch (error) {
      setNotice({ kind: "error", text: error instanceof Error ? error.message : "Rebalance failed." });
    } finally {
      setBusy(null);
    }
  }

  async function poke() {
    setNotice(null);
    if (!publicClient || !isCurator || wrongChain) return;
    setBusy("Update ranking");
    try {
      const hash = await writeContractAsync({
        address: vault,
        abi: RudderVaultAbi,
        functionName: "pokeAlpha",
      });
      await publicClient.waitForTransactionReceipt({ hash });
      setNotice({ kind: "ok", text: "Ranking update confirmed.", hash });
    } catch (error) {
      setNotice({ kind: "error", text: error instanceof Error ? error.message : "Ranking update failed." });
    } finally {
      setBusy(null);
    }
  }

  return (
    <section className="border-t border-rule py-8" aria-labelledby={`console-${curator.id}`}>
      <div className="flex flex-wrap items-start justify-between gap-4">
        <div>
          <h2 id={`console-${curator.id}`} className="text-xl">
            Strategy {curator.id}
          </h2>
          <p className="mt-1 text-sm text-slate">
            Vault {shortAddress(vault)} · curator {assigned.data ? shortAddress(assigned.data) : "--"} · liquidity{" "}
            {liquidity.data !== undefined ? formatCount(liquidity.data) : "--"}
          </p>
        </div>
        <Link className="text-sm text-ink underline" href={`/vaults/${curator.id}/`}>
          Open detail
        </Link>
      </div>
      <p className="mt-4 text-sm">
        {!owner ? "Connect a wallet to check curator permission." : isCurator ? "Permission: curator" : "Permission: read only"}
        {!oracleReady ? " · Price feed is not ready for rebalances." : ""}
      </p>
      <div className="mt-6 flex flex-wrap gap-6">
        <label className="text-sm">
          Lower tick
          <input
            className="field mt-2 w-36"
            type="number"
            value={lower}
            onChange={(event) => setLower(event.target.value)}
            disabled={!isCurator || Boolean(busy)}
          />
        </label>
        <label className="text-sm">
          Upper tick
          <input
            className="field mt-2 w-36"
            type="number"
            value={upper}
            onChange={(event) => setUpper(event.target.value)}
            disabled={!isCurator || Boolean(busy)}
          />
        </label>
        <div className="flex items-end gap-2">
          <button
            type="button"
            className="button"
            disabled={!canRebalance || Boolean(busy)}
            onClick={() => void rebalance()}
          >
            {busy === "Rebalance" ? "Rebalance…" : "Rebalance"}
          </button>
          <button
            type="button"
            className="button-secondary"
            disabled={!isCurator || wrongChain || Boolean(busy)}
            onClick={() => void poke()}
          >
            {busy === "Update ranking" ? "Updating ranking…" : "Update ranking"}
          </button>
        </div>
      </div>
      {reasons.length ? (
        <ul className="mt-4 list-disc pl-5 text-sm text-slate">
          {reasons.map((reason) => (
            <li key={reason}>{reason}</li>
          ))}
        </ul>
      ) : (
        <p className="mt-4 text-sm text-slate">
          Local check passed. The vault enforces the same limits on-chain before any rebalance.
        </p>
      )}
      {notice ? (
        <p className="mt-4 text-sm text-ink" role="status">
          {notice.text}{" "}
          {notice.hash ? (
            <Link className="underline" href={explorerTx(notice.hash)} target="_blank" rel="noreferrer">
              View transaction
            </Link>
          ) : null}
        </p>
      ) : null}
    </section>
  );
}

export default function ConsolePanel() {
  const { data, isError, refetch } = useChainData();
  const { address, isConnected, chainId } = useAccount();
  const { switchChainAsync } = useSwitchChain();
  const wrongChain = isConnected && chainId !== unichainSepolia.id;
  const twap = data.twap[0]?.tick ?? 0;
  const oracleReady = data.oracle.ready && !data.oracle.paused && data.oracle.samples >= 2;

  return (
    <section>
      <div className="flex flex-wrap items-end justify-between gap-4">
        <div>
          <p className="text-sm text-slate">Curator-only writes</p>
          <h2 className="mt-2 text-2xl">Strategy controls</h2>
        </div>
        <ChainStatus {...data} />
      </div>
      {isError ? <ErrorPanel message="The controls could not read the chain." onRetry={() => void refetch()} /> : null}
      {!isConnected ? <EmptyPanel message="Connect the curator wallet to enable writes." /> : null}
      {wrongChain ? (
        <div className="mt-6 border-y border-rule py-4 text-sm">
          <p>Switch to Unichain Sepolia to continue.</p>
          <button
            type="button"
            className="button-secondary mt-3"
            onClick={() => void switchChainAsync({ chainId: unichainSepolia.id }).catch(() => undefined)}
          >
            Switch network
          </button>
        </div>
      ) : null}
      {data.curators.length === 0 ? <EmptyPanel message="No strategies are registered." /> : null}
      {data.curators.map((curator) => (
        <ConsoleRow
          key={curator.id}
          curator={curator}
          twap={twap}
          owner={address}
          wrongChain={wrongChain}
          oracleReady={oracleReady}
        />
      ))}
    </section>
  );
}
