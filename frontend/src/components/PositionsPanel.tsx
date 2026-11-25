"use client";

import Link from "next/link";
import { useState } from "react";
import { formatUnits, zeroAddress } from "viem";
import {
  useAccount,
  usePublicClient,
  useReadContract,
  useSwitchChain,
  useWriteContract,
} from "wagmi";
import { RudderVaultAbi, VaultMigratorAbi } from "@/abis";
import { CHAIN_ID, explorerTx, migratorAddress, shortAddress, unichainSepolia } from "@/lib/chain";
import { useChainData } from "@/lib/chainData";
import { formatCount } from "@/lib/format";
import { ChainStatus, EmptyPanel, ErrorPanel, LoadingPanel } from "@/components/StatePanels";
import type { Curator } from "@/lib/types";

type Notice = { kind: "ok" | "error"; text: string; hash?: string };

interface RowProps {
  curator: Curator;
  options: Curator[];
  owner: `0x${string}`;
  wrongChain: boolean;
}

function PositionRow({ curator, options, owner, wrongChain }: RowProps) {
  const vault = curator.vault as `0x${string}`;
  const publicClient = usePublicClient({ chainId: unichainSepolia.id });
  const { writeContractAsync } = useWriteContract();
  const [destination, setDestination] = useState("");
  const [busy, setBusy] = useState<string | null>(null);
  const [notice, setNotice] = useState<Notice | null>(null);
  const migrator = migratorAddress || undefined;

  const shares = useReadContract({
    address: vault,
    abi: RudderVaultAbi,
    functionName: "balanceOf",
    args: [owner],
  });
  const fees0 = useReadContract({
    address: vault,
    abi: RudderVaultAbi,
    functionName: "pendingFees0",
  });
  const fees1 = useReadContract({
    address: vault,
    abi: RudderVaultAbi,
    functionName: "pendingFees1",
  });
  const approval = useReadContract({
    address: vault,
    abi: RudderVaultAbi,
    functionName: "allowance",
    args: [owner, migrator ?? zeroAddress],
    query: { enabled: Boolean(migrator) },
  });

  async function claim() {
    setNotice(null);
    if (!publicClient || wrongChain) return;
    setBusy("Claim fees");
    try {
      const hash = await writeContractAsync({
        address: vault,
        abi: RudderVaultAbi,
        functionName: "claimFees",
      });
      await publicClient.waitForTransactionReceipt({ hash });
      setNotice({ kind: "ok", text: "Claim fees confirmed.", hash });
    } catch (error) {
      setNotice({ kind: "error", text: error instanceof Error ? error.message : "Claim fees failed." });
    } finally {
      setBusy(null);
    }
  }

  async function migrate() {
    setNotice(null);
    if (!migrator || !publicClient || wrongChain || !destination) return;
    setBusy("Migrate");
    try {
      const to = destination as `0x${string}`;
      if (approval.data === undefined || approval.data < (shares.data ?? 0n)) {
        const approveHash = await writeContractAsync({
          address: vault,
          abi: RudderVaultAbi,
          functionName: "approve",
          args: [migrator, shares.data ?? 0n],
        });
        await publicClient.waitForTransactionReceipt({ hash: approveHash });
      }
      const hash = await writeContractAsync({
        address: migrator,
        abi: VaultMigratorAbi,
        functionName: "migrate",
        args: [vault, to],
      });
      await publicClient.waitForTransactionReceipt({ hash });
      setNotice({ kind: "ok", text: "Migrate confirmed.", hash });
    } catch (error) {
      setNotice({ kind: "error", text: error instanceof Error ? error.message : "Migrate failed." });
    } finally {
      setBusy(null);
    }
  }

  const hasPosition = shares.data !== undefined && shares.data > 0n;
  const hasFees = (fees0.data ?? 0n) > 0n || (fees1.data ?? 0n) > 0n;
  const allowed = Boolean(migrator && approval.data !== undefined && approval.data >= (shares.data ?? 0n));

  return (
    <tr>
      <td>
        <Link className="text-ink underline" href={`/curators/${curator.id}/`}>
          Strategy {curator.id}
        </Link>
        <p className="mt-1 text-xs text-slate">{shortAddress(vault)}</p>
      </td>
      <td>{shares.data !== undefined ? formatUnits(shares.data, 18) : "--"}</td>
      <td>
        {fees0.data !== undefined && fees1.data !== undefined
          ? `${formatUnits(fees0.data, 18)} / ${formatUnits(fees1.data, 18)}`
          : "--"}
      </td>
      <td>{!migrator ? "Contract not deployed" : allowed ? "Approved" : "Approve needed"}</td>
      <td>
        <div className="flex flex-wrap items-center gap-2">
          <button
            type="button"
            className="action action-quiet min-h-0 px-2 py-1 text-xs"
            disabled={!hasFees || wrongChain || Boolean(busy)}
            onClick={() => void claim()}
          >
            {busy === "Claim fees" ? "Claim fees…" : "Claim fees"}
          </button>
          <select
            className="border border-rule bg-paper px-2 py-1 text-xs"
            aria-label={`Migrate strategy ${curator.id} destination`}
            value={destination}
            onChange={(event) => setDestination(event.target.value)}
            disabled={!hasPosition || !migrator || Boolean(busy)}
          >
            <option value="">Migrate to…</option>
            {options
              .filter((entry) => entry.id !== curator.id)
              .map((entry) => (
                <option key={entry.id} value={entry.vault}>
                  Strategy {entry.id}
                </option>
              ))}
          </select>
          <button
            type="button"
            className="action min-h-0 px-2 py-1 text-xs"
            disabled={!hasPosition || !migrator || !destination || wrongChain || Boolean(busy)}
            onClick={() => void migrate()}
          >
            {busy === "Migrate" ? "Migrate…" : "Migrate"}
          </button>
        </div>
        {notice ? (
          <p className={`mt-2 text-xs ${notice.kind === "ok" ? "text-ink" : "text-signal"}`} role="status">
            {notice.text}{" "}
            {notice.hash ? (
              <Link className="underline" href={explorerTx(notice.hash)} target="_blank" rel="noreferrer">
                View transaction
              </Link>
            ) : null}
          </p>
        ) : null}
      </td>
    </tr>
  );
}

export default function PositionsPanel() {
  const { data, isLoading, isError, refetch } = useChainData();
  const { address, isConnected, chainId } = useAccount();
  const { switchChainAsync } = useSwitchChain();
  const wrongChain = isConnected && chainId !== unichainSepolia.id;
  const migrator = migratorAddress || undefined;

  return (
    <section>
      <div className="flex flex-wrap items-end justify-between gap-4">
        <div>
          <p className="eyebrow">Connected wallet</p>
          <h2 className="mt-2 text-2xl">My positions</h2>
        </div>
        <ChainStatus {...data} />
      </div>
      {isLoading ? <LoadingPanel label="Reading positions" /> : null}
      {isError ? <ErrorPanel message="Positions could not be read." onRetry={() => void refetch()} /> : null}
      {!isConnected ? (
        <EmptyPanel message="Connect a wallet from the header to see shares, fees and permissions." />
      ) : null}
      {wrongChain ? (
        <div className="mt-6 border-y border-rule py-4 text-sm">
          <p>Switch to Unichain Sepolia to read and change positions.</p>
          <button
            type="button"
            className="action action-quiet mt-3"
            onClick={() => void switchChainAsync({ chainId: unichainSepolia.id }).catch(() => undefined)}
          >
            Switch network
          </button>
        </div>
      ) : null}
      {isConnected && !wrongChain && address ? (
        <div className="table-scroll mt-8">
          <table className="data-table">
            <caption className="sr-only">Vault shares, unclaimed fees and migration permissions</caption>
            <thead>
              <tr>
                <th scope="col">Vault</th>
                <th scope="col">Shares</th>
                <th scope="col">Fees A / B</th>
                <th scope="col">Permission</th>
                <th scope="col">Actions</th>
              </tr>
            </thead>
            <tbody>
              {data.curators.map((curator) => (
                <PositionRow
                  key={curator.id}
                  curator={curator}
                  options={data.curators}
                  owner={address}
                  wrongChain={wrongChain}
                />
              ))}
            </tbody>
          </table>
        </div>
      ) : null}
      <p className="mt-6 text-sm text-slate">
        {migrator
          ? `Migrator: ${shortAddress(migrator)} · moves a full position in one signed transaction.`
          : `The migrator is not in the deployment record for chain ${formatCount(CHAIN_ID)}. Verify a VaultMigrator before setting NEXT_PUBLIC_MIGRATOR_ADDRESS.`}
      </p>
    </section>
  );
}
