"use client";

import { useAccount, useConnect, useDisconnect, useSwitchChain } from "wagmi";
import { unichainSepolia } from "@/lib/chain";
import { shortAddress } from "@/lib/chain";

export default function WalletButton() {
  const { address, chainId, isConnected } = useAccount();
  const { connectAsync, connectors, isPending: isConnecting } = useConnect();
  const { disconnect } = useDisconnect();
  const { switchChainAsync, isPending: isSwitching } = useSwitchChain();
  const wrongChain = isConnected && chainId !== unichainSepolia.id;
  const label = !isConnected
    ? isConnecting
      ? "Connecting…"
      : "Connect wallet"
    : wrongChain
      ? isSwitching
        ? "Switching…"
        : "Switch to Unichain Sepolia"
      : shortAddress(address);

  return (
    <div className="flex items-center gap-2">
      <button
        type="button"
        className="action action-quiet min-h-0 px-3 py-1 text-xs"
        disabled={isConnecting || isSwitching}
        onClick={() => {
          if (!isConnected) {
            const connector = connectors[0];
            if (connector) void connectAsync({ connector }).catch(() => undefined);
          } else if (wrongChain) {
            void switchChainAsync({ chainId: unichainSepolia.id }).catch(() => undefined);
          }
        }}
      >
        {label}
      </button>
      {isConnected ? (
        <button type="button" className="text-xs text-slate underline" onClick={() => disconnect()}>
          Disconnect
        </button>
      ) : null}
    </div>
  );
}
