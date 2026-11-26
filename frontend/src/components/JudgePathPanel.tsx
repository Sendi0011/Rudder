"use client";

import Link from "next/link";
import { useState } from "react";
import { parseUnits } from "viem";
import { useAccount, usePublicClient, useSwitchChain, useWriteContract } from "wagmi";
import { TestERC20Abi } from "@/abis";
import ActionDrawer from "@/components/ActionDrawer";
import { ChainStatus } from "@/components/StatePanels";
import { addresses, explorerTx, shortAddress, unichainSepolia } from "@/lib/chain";
import { useChainData } from "@/lib/chainData";
import { formatCount } from "@/lib/format";
import { snapshot } from "@/lib/snapshot";

export default function JudgePathPanel() {
  const { data } = useChainData();
  const { address, isConnected, chainId } = useAccount();
  const publicClient = usePublicClient({ chainId: unichainSepolia.id });
  const { switchChainAsync } = useSwitchChain();
  const { writeContractAsync } = useWriteContract();
  const [depositOpen, setDepositOpen] = useState(false);
  const [withdrawOpen, setWithdrawOpen] = useState(false);
  const [busy, setBusy] = useState(false);
  const [notice, setNotice] = useState<{ ok: boolean; text: string; hash?: string } | null>(null);
  const wrongChain = isConnected && chainId !== unichainSepolia.id;

  async function mint() {
    setNotice(null);
    if (!address || !publicClient || wrongChain) return;
    setBusy(true);
    try {
      const amount = parseUnits("1000", 18);
      const first = await writeContractAsync({
        address: addresses.token0,
        abi: TestERC20Abi,
        functionName: "mint",
        args: [address, amount],
      });
      await publicClient.waitForTransactionReceipt({ hash: first });
      const second = await writeContractAsync({
        address: addresses.token1,
        abi: TestERC20Abi,
        functionName: "mint",
        args: [address, amount],
      });
      await publicClient.waitForTransactionReceipt({ hash: second });
      setNotice({ ok: true, text: "Mint confirmed for 1,000 token A and 1,000 token B.", hash: second });
    } catch (error) {
      setNotice({ ok: false, text: error instanceof Error ? error.message : "Mint failed." });
    } finally {
      setBusy(false);
    }
  }

  return (
    <section>
      <ChainStatus {...data} />
      {!isConnected ? (
        <p className="mt-6 border-y border-rule py-4 text-sm">
          Connect a browser wallet from the header. The app never asks for a key.
        </p>
      ) : null}
      {wrongChain ? (
        <div className="mt-6 border-y border-rule py-4 text-sm">
          <p>Switch to Unichain Sepolia before minting or depositing.</p>
          <button
            type="button"
            className="button-secondary mt-3"
            onClick={() => void switchChainAsync({ chainId: unichainSepolia.id }).catch(() => undefined)}
          >
            Switch network
          </button>
        </div>
      ) : null}

      <div className="mt-10 grid gap-0">
        <div className="border-t border-rule py-6">
          <h2 className="text-lg font-semibold">Fund</h2>
          <h3 className="mt-1 text-xl">Mint test tokens</h3>
          <p className="mt-2 max-w-2xl text-sm text-slate">
            The test tokens are on Unichain Sepolia and have no value. Your wallet signs two mint calls.
          </p>
          <button
            type="button"
            className="button mt-4"
            disabled={!isConnected || wrongChain || busy}
            onClick={() => void mint()}
          >
            {busy ? "Mint…" : "Mint"}
          </button>
        </div>
        <div className="border-t border-rule py-6">
          <h2 className="text-lg font-semibold">Try</h2>
          <h3 className="mt-1 text-xl">Deposit into a vault</h3>
          <p className="mt-2 max-w-2xl text-sm text-slate">
            Approve each token if needed, then deposit into strategy 0. The same drawer can withdraw
            your shares later.
          </p>
          <button
            type="button"
            className="button mt-4"
            disabled={!isConnected || wrongChain}
            onClick={() => setDepositOpen(true)}
          >
            Deposit
          </button>
        </div>
        <div className="border-t border-rule py-6">
          <h2 className="text-lg font-semibold">Prove</h2>
          <h3 className="mt-1 text-xl">Watch a rejected rebalance</h3>
          <p className="mt-2 max-w-2xl text-sm text-slate">
            A live simulation calls the deployed vault as the curator, with a range deliberately outside
            the published limits. Nothing is signed or broadcast.
          </p>
          <Link className="button-secondary mt-4 inline-flex" href="/proof/">
            Simulate rebalance
          </Link>
        </div>
        <div className="border-b border-t border-rule py-6">
          <h2 className="text-lg font-semibold">Exit</h2>
          <h3 className="mt-1 text-xl">Withdraw and inspect</h3>
          <p className="mt-2 max-w-2xl text-sm text-slate">
            Withdraw shares or open your deposits to see unclaimed fees and migration permission.
          </p>
          <div className="mt-4 flex flex-wrap gap-3">
            <button
              type="button"
              className="button"
              disabled={!isConnected || wrongChain}
              onClick={() => setWithdrawOpen(true)}
            >
              Withdraw
            </button>
            <Link className="button-secondary inline-flex" href="/deposits/">
              Your deposits
            </Link>
          </div>
        </div>
      </div>

      {notice ? (
        <p className="mt-6 text-sm text-ink" role="status">
          {notice.text}{" "}
          {notice.hash ? (
            <Link className="underline" href={explorerTx(notice.hash)} target="_blank" rel="noreferrer">
              View transaction
            </Link>
          ) : null}
        </p>
      ) : null}

      <div className="mt-12 border-t border-rule pt-6">
        <h2 className="text-xl">Recorded chain state</h2>
        <p className="mt-2 max-w-2xl text-sm text-slate">
          If a read fails, the app shows this recorded state instead of invented numbers. It was
          captured at {snapshot.recordedAt} from a read-only RPC.
        </p>
        <dl className="mt-4 grid gap-3 text-sm sm:grid-cols-3">
          <div>
            <dt className="text-slate">Source</dt>
            <dd>{data.source === "live" ? "Live RPC" : "Snapshot"}</dd>
          </div>
          <div>
            <dt className="text-slate">Strategies</dt>
            <dd className="numeric">{formatCount(snapshot.curators.length)}</dd>
          </div>
          <div>
            <dt className="text-slate">Rebalances</dt>
            <dd className="numeric">{formatCount(snapshot.rebalances.length)}</dd>
          </div>
          <div>
            <dt className="text-slate">Price feed</dt>
            <dd>{snapshot.oracle.ready ? "Ready" : "Not ready"} · {formatCount(snapshot.oracle.samples)} samples</dd>
          </div>
          <div>
            <dt className="text-slate">Curator</dt>
            <dd>{shortAddress(snapshot.curators[0]?.curator)}</dd>
          </div>
          <div>
            <dt className="text-slate">Average price</dt>
            <dd className="numeric">{snapshot.twap[0]?.tick ?? "--"} ticks</dd>
          </div>
        </dl>
      </div>

      <ActionDrawer open={depositOpen} onOpenChange={setDepositOpen} defaultCuratorId={0} defaultTab="deposit" />
      <ActionDrawer open={withdrawOpen} onOpenChange={setWithdrawOpen} defaultCuratorId={0} defaultTab="withdraw" />
    </section>
  );
}
