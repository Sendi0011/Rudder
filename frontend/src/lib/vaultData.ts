"use client";

import { useQuery } from "@tanstack/react-query";
import type { PublicClient } from "viem";
import { usePublicClient } from "wagmi";
import { RudderHookAbi } from "@/abis/RudderHook";
import { RudderVaultAbi } from "@/abis/RudderVault";
import { addresses, CHAIN_ID, poolKey } from "@/lib/chain";
import { sqrtPriceX96ToTick } from "@/lib/price";

export interface VaultDetails {
  twapSqrtPriceX96: bigint;
  twapTick: number;
  baseNavPerShare: bigint;
  baseHoldValuePerShare: bigint;
  totalHold0: bigint;
  totalHold1: bigint;
  pendingFees0: bigint;
  pendingFees1: bigint;
  lossBucket: bigint;
  lossBucketUpdated: number;
  paused: boolean;
}

export function useVaultDetails(vault?: `0x${string}`) {
  const client = usePublicClient({ chainId: CHAIN_ID });
  return useQuery<VaultDetails>({
    queryKey: ["rudder", "vault", vault, CHAIN_ID],
    enabled: Boolean(client && vault),
    queryFn: async () => {
      if (!client || !vault) throw new Error("No client or vault");
      const [twapSqrtPriceX96, baseNavPerShare, baseHoldValuePerShare, hold, pendingFees0, pendingFees1, lossBucket, lossBucketUpdated, paused] =
        await Promise.all([
          client.readContract({ address: addresses.hook, abi: RudderHookAbi, functionName: "consult", args: [poolKey, 0] }),
          client.readContract({ address: vault, abi: RudderVaultAbi, functionName: "baseNavPerShare" }),
          client.readContract({ address: vault, abi: RudderVaultAbi, functionName: "baseHoldValuePerShare" }),
          client.readContract({ address: vault, abi: RudderVaultAbi, functionName: "totalHold" }),
          client.readContract({ address: vault, abi: RudderVaultAbi, functionName: "pendingFees0" }),
          client.readContract({ address: vault, abi: RudderVaultAbi, functionName: "pendingFees1" }),
          client.readContract({ address: vault, abi: RudderVaultAbi, functionName: "lossBucket" }),
          client.readContract({ address: vault, abi: RudderVaultAbi, functionName: "lastBucketUpdate" }),
          client.readContract({ address: addresses.hook, abi: RudderHookAbi, functionName: "paused" }),
        ]);
      return {
        twapSqrtPriceX96,
        twapTick: sqrtPriceX96ToTick(twapSqrtPriceX96),
        baseNavPerShare,
        baseHoldValuePerShare,
        totalHold0: hold[0],
        totalHold1: hold[1],
        pendingFees0,
        pendingFees1,
        lossBucket,
        lossBucketUpdated: Number(lossBucketUpdated),
        paused,
      };
    },
  });
}

export async function readTwapAtOffset(client: PublicClient, secondsAgo: number) {
  const sqrt = await client.readContract({
    address: addresses.hook,
    abi: RudderHookAbi,
    functionName: "consult",
    args: [poolKey, secondsAgo],
  });
  return { sqrt, tick: sqrtPriceX96ToTick(sqrt) };
}
