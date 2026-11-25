"use client";

import * as Dialog from "@radix-ui/react-dialog";
import * as Tabs from "@radix-ui/react-tabs";
import Link from "next/link";
import { useEffect, useState } from "react";
import { formatUnits, parseUnits, zeroAddress } from "viem";
import {
  useAccount,
  usePublicClient,
  useReadContract,
  useSwitchChain,
  useWriteContract,
} from "wagmi";
import { RudderVaultAbi, TestERC20Abi } from "@/abis";
import { addresses, explorerTx, shortAddress, unichainSepolia } from "@/lib/chain";
import { useChainData } from "@/lib/chainData";
import { formatCount } from "@/lib/format";

interface Props {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  defaultCuratorId?: number;
}

function toUnits(value: string): bigint | null {
  if (!value.trim()) return 0n;
  try {
    return parseUnits(value, 18);
  } catch {
    return null;
  }
}

export default function ActionDrawer({ open, onOpenChange, defaultCuratorId = 0 }: Props) {
  const { data } = useChainData();
  const { address, chainId, isConnected } = useAccount();
  const publicClient = usePublicClient({ chainId: unichainSepolia.id });
  const { switchChainAsync } = useSwitchChain();
  const { writeContractAsync } = useWriteContract();
  const [tab, setTab] = useState("deposit");
  const [curatorId, setCuratorId] = useState(defaultCuratorId);
  const [amount0, setAmount0] = useState("");
  const [amount1, setAmount1] = useState("");
  const [shares, setShares] = useState("");
  const [busy, setBusy] = useState<string | null>(null);
  const [result, setResult] = useState<{ kind: "ok" | "error"; text: string; hash?: string } | null>(
    null,
  );

  useEffect(() => {
    if (open) setCuratorId(defaultCuratorId);
  }, [open, defaultCuratorId]);

  const curator = data.curators.find((entry) => entry.id === curatorId) ?? data.curators[0];
  const vault = (curator?.vault ?? addresses.vaults[0] ?? zeroAddress) as `0x${string}`;
  const enabled = Boolean(address && isConnected);
  const owner = address ?? zeroAddress;
  const wrongChain = isConnected && chainId !== unichainSepolia.id;

  const balance0 = useReadContract({
    address: addresses.token0,
    abi: TestERC20Abi,
    functionName: "balanceOf",
    args: [owner],
    query: { enabled },
  });
  const balance1 = useReadContract({
    address: addresses.token1,
    abi: TestERC20Abi,
    functionName: "balanceOf",
    args: [owner],
    query: { enabled },
  });
  const shareBalance = useReadContract({
    address: vault,
    abi: RudderVaultAbi,
    functionName: "balanceOf",
    args: [owner],
    query: { enabled: Boolean(enabled && vault) },
  });
  const allowance0 = useReadContract({
    address: addresses.token0,
    abi: TestERC20Abi,
    functionName: "allowance",
    args: [owner, vault],
    query: { enabled: Boolean(enabled && vault) },
  });
  const allowance1 = useReadContract({
    address: addresses.token1,
    abi: TestERC20Abi,
    functionName: "allowance",
    args: [owner, vault],
    query: { enabled: Boolean(enabled && vault) },
  });

  async function ensureApproval(token: `0x${string}`, amount: bigint) {
    if (amount === 0n) return;
    const current = token === addresses.token0 ? allowance0.data : allowance1.data;
    if (current !== undefined && current >= amount) return;
    if (!publicClient) throw new Error("Public RPC is not ready.");
    const hash = await writeContractAsync({
      address: token,
      abi: TestERC20Abi,
      functionName: "approve",
      args: [vault, amount],
    });
    await publicClient.waitForTransactionReceipt({ hash });
  }

  async function submit() {
    setResult(null);
    if (!address || !isConnected) {
      setResult({ kind: "error", text: "Connect a wallet first." });
      return;
    }
    if (wrongChain) return;
    if (!publicClient) {
      setResult({ kind: "error", text: "Public RPC is not ready." });
      return;
    }

    try {
      if (tab === "deposit") {
        const a0 = toUnits(amount0);
        const a1 = toUnits(amount1);
        if (a0 === null || a1 === null || (a0 === 0n && a1 === 0n)) {
          setResult({ kind: "error", text: "Enter a nonzero amount in token A or token B." });
          return;
        }
        setBusy("Deposit");
        await ensureApproval(addresses.token0, a0);
        await ensureApproval(addresses.token1, a1);
        const hash = await writeContractAsync({
          address: vault,
          abi: RudderVaultAbi,
          functionName: "deposit",
          args: [a0, a1, address],
        });
        await publicClient.waitForTransactionReceipt({ hash });
        setResult({ kind: "ok", text: "Deposit confirmed in this vault.", hash });
      } else {
        const parsed = toUnits(shares);
        if (parsed === null || parsed === 0n) {
          setResult({ kind: "error", text: "Enter a nonzero share amount." });
          return;
        }
        setBusy("Withdraw");
        const hash = await writeContractAsync({
          address: vault,
          abi: RudderVaultAbi,
          functionName: "withdraw",
          args: [parsed, address],
        });
        await publicClient.waitForTransactionReceipt({ hash });
        setResult({ kind: "ok", text: "Withdraw confirmed from this vault.", hash });
      }
    } catch (error) {
      setResult({
        kind: "error",
        text: error instanceof Error ? error.message : "The transaction failed.",
      });
    } finally {
      setBusy(null);
    }
  }

  return (
    <Dialog.Root open={open} onOpenChange={onOpenChange}>
      <Dialog.Portal>
        <Dialog.Overlay className="fixed inset-0 bg-ink/35" />
        <Dialog.Content className="fixed right-0 top-0 h-full w-full max-w-lg overflow-y-auto border-l border-rule bg-paper p-6 shadow-xl focus:outline-none sm:p-8">
          <div className="flex items-start justify-between gap-4">
            <div>
              <p className="eyebrow">Unichain Sepolia · browser wallet only</p>
              <Dialog.Title className="mt-1 text-2xl">Deposit or withdraw</Dialog.Title>
              <Dialog.Description className="mt-2 text-sm text-slate">
                Your wallet signs every transaction. No key is requested, stored or sent to this app.
              </Dialog.Description>
            </div>
            <Dialog.Close className="action action-quiet min-h-0 px-2 py-1 text-xs" aria-label="Close">
              Close
            </Dialog.Close>
          </div>

          {!isConnected ? (
            <p className="mt-8 border-y border-rule py-4 text-sm">
              Connect a wallet from the header to continue. The app never asks for a private key.
            </p>
          ) : null}
          {wrongChain ? (
            <div className="mt-8 border-y border-rule py-4 text-sm">
              <p>This wallet is on chain {chainId ?? "--"}. Switch to Unichain Sepolia.</p>
              <button
                type="button"
                className="action action-quiet mt-3"
                onClick={() => void switchChainAsync({ chainId: unichainSepolia.id }).catch(() => undefined)}
              >
                Switch network
              </button>
            </div>
          ) : null}

          <label className="mt-8 block text-sm">
            Strategy vault
            <select
              className="mt-2 w-full border border-rule bg-paper px-3 py-2"
              value={curator?.id ?? 0}
              onChange={(event) => setCuratorId(Number(event.target.value))}
              disabled={Boolean(busy)}
            >
              {data.curators.map((entry) => (
                <option key={entry.id} value={entry.id}>
                  Strategy {entry.id} · {shortAddress(entry.curator)}
                </option>
              ))}
            </select>
          </label>

          {curator ? (
            <p className="mt-2 text-xs text-slate">
              Limits: ±{formatCount(curator.envelope.maxTwapDistanceTicks)} ticks from the TWAP.
              Deposits and withdrawals always use these on-chain limits.
            </p>
          ) : null}

          <Tabs.Root value={tab} onValueChange={setTab} className="mt-8">
            <Tabs.List className="flex gap-2 border-b border-rule" aria-label="Action">
              <Tabs.Trigger value="deposit" className="px-3 py-2 text-sm data-[state=active]:border-b-2 data-[state=active]:border-cobalt data-[state=active]:text-ink">
                Deposit
              </Tabs.Trigger>
              <Tabs.Trigger value="withdraw" className="px-3 py-2 text-sm data-[state=active]:border-b-2 data-[state=active]:border-cobalt data-[state=active]:text-ink">
                Withdraw
              </Tabs.Trigger>
            </Tabs.List>
            <Tabs.Content value="deposit" className="pt-6">
              <p className="mb-4 text-xs text-slate">
                Token A balance: {balance0.data !== undefined ? formatUnits(balance0.data, 18) : "--"} · Token B balance:{" "}
                {balance1.data !== undefined ? formatUnits(balance1.data, 18) : "--"}
              </p>
              <label className="block text-sm">
                Token A amount
                <input
                  className="mt-2 w-full border border-rule bg-paper px-3 py-2"
                  inputMode="decimal"
                  value={amount0}
                  onChange={(event) => setAmount0(event.target.value)}
                  placeholder="0.0"
                  disabled={Boolean(busy)}
                />
              </label>
              <label className="mt-4 block text-sm">
                Token B amount
                <input
                  className="mt-2 w-full border border-rule bg-paper px-3 py-2"
                  inputMode="decimal"
                  value={amount1}
                  onChange={(event) => setAmount1(event.target.value)}
                  placeholder="0.0"
                  disabled={Boolean(busy)}
                />
              </label>
            </Tabs.Content>
            <Tabs.Content value="withdraw" className="pt-6">
              <p className="mb-4 text-xs text-slate">
                Your shares: {shareBalance.data !== undefined ? formatUnits(shareBalance.data, 18) : "--"}
              </p>
              <label className="block text-sm">
                Shares to withdraw
                <input
                  className="mt-2 w-full border border-rule bg-paper px-3 py-2"
                  inputMode="decimal"
                  value={shares}
                  onChange={(event) => setShares(event.target.value)}
                  placeholder="0.0"
                  disabled={Boolean(busy)}
                />
              </label>
            </Tabs.Content>
          </Tabs.Root>

          <button
            type="button"
            className="action mt-8 w-full"
            disabled={!isConnected || wrongChain || Boolean(busy)}
            onClick={() => void submit()}
          >
            {busy ? `${busy}…` : tab === "deposit" ? "Deposit" : "Withdraw"}
          </button>
          {busy ? <p className="mt-3 text-sm text-slate">Waiting for your wallet and the chain…</p> : null}
          {result ? (
            <p className={`mt-4 text-sm ${result.kind === "ok" ? "text-ink" : "text-signal"}`} role="status">
              {result.text}{" "}
              {result.hash ? (
                <Link className="underline" href={explorerTx(result.hash)} target="_blank" rel="noreferrer">
                  View transaction
                </Link>
              ) : null}
            </p>
          ) : null}
        </Dialog.Content>
      </Dialog.Portal>
    </Dialog.Root>
  );
}
