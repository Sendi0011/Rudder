import { defineChain } from "viem";
import deployments from "@/data/deployments.json";
import seed from "@/data/seed.json";

export const CHAIN_ID = 1301 as const;

export const rpcUrl =
  process.env.NEXT_PUBLIC_UNICHAIN_SEPOLIA_RPC_URL || "https://sepolia.unichain.org";

export const unichainSepolia = defineChain({
  id: CHAIN_ID,
  name: "Unichain Sepolia",
  nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
  rpcUrls: { default: { http: [rpcUrl] } },
  blockExplorers: {
    default: { name: "Uniscan", url: "https://sepolia.uniscan.xyz" },
  },
  testnet: true,
});

export const addresses = {
  poolManager: deployments.poolManager as `0x${string}`,
  hook: deployments.rudderHook as `0x${string}`,
  registry: deployments.strategyRegistry as `0x${string}`,
  factory: deployments.vaultFactory as `0x${string}`,
  implementation: deployments.vaultImplementation as `0x${string}`,
  token0: seed.token0 as `0x${string}`,
  token1: seed.token1 as `0x${string}`,
  router: seed.router as `0x${string}`,
  vaults: [seed.vault0, seed.vault1, seed.vault2] as `0x${string}`[],
} as const;

export const poolKey = {
  currency0: addresses.token0,
  currency1: addresses.token1,
  fee: seed.fee,
  tickSpacing: seed.tickSpacing,
  hooks: addresses.hook,
} as const;

export function explorerAddress(address: string) {
  return `https://sepolia.uniscan.xyz/address/${address}`;
}

export function explorerTx(hash: string) {
  return `https://sepolia.uniscan.xyz/tx/${hash}`;
}

export function shortAddress(address?: string | null) {
  if (!address) return "--";
  return `${address.slice(0, 6)}…${address.slice(-4)}`;
}
