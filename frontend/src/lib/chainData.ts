"use client";

import { useQuery } from "@tanstack/react-query";
import type { PublicClient } from "viem";
import { usePublicClient } from "wagmi";
import { RudderHookAbi } from "@/abis/RudderHook";
import { RudderVaultAbi } from "@/abis/RudderVault";
import { StrategyRegistryAbi } from "@/abis/StrategyRegistry";
import { addresses, CHAIN_ID, poolKey } from "@/lib/chain";
import { snapshot } from "@/lib/snapshot";
import type { ChainSnapshot, Curator, Envelope, RebalanceRecord } from "@/lib/types";
import { readTwapAtOffset } from "@/lib/vaultData";

const DEPLOYMENT_BLOCK = 68_669_835n;
const MAX_LOG_BLOCKS = 1000n;
const MAX_LOG_HISTORY = 80_000n;

const rebalanceEvent = RudderVaultAbi.find(
  (entry) => entry.type === "event" && entry.name === "Rebalance",
);

async function fetchRebalances(client: PublicClient): Promise<RebalanceRecord[]> {
  if (!rebalanceEvent) throw new Error("Rebalance event missing from generated ABI");
  const latest = await client.getBlockNumber();
  const lowerBound = latest - MAX_LOG_HISTORY;
  const from = DEPLOYMENT_BLOCK > lowerBound ? DEPLOYMENT_BLOCK : lowerBound;
  const windows: { from: bigint; to: bigint }[] = [];
  for (let start = from; start <= latest; start += MAX_LOG_BLOCKS + 1n) {
    const to = start + MAX_LOG_BLOCKS > latest ? latest : start + MAX_LOG_BLOCKS;
    windows.push({ from: start, to });
  }

  const logs: (Awaited<ReturnType<PublicClient["getLogs"]>>[number] & {
    args: { strategyId?: bigint; tickLower?: number; tickUpper?: number; liquidity?: bigint };
  })[] = [];
  for (let index = 0; index < windows.length; index += 8) {
    const batch = await Promise.all(
      windows.slice(index, index + 8).map((window) =>
        client
          .getLogs({
            address: addresses.vaults,
            event: rebalanceEvent,
            fromBlock: window.from,
            toBlock: window.to,
          })
          .catch(() => []),
      ),
    );
    logs.push(...batch.flat() as typeof logs);
  }

  const blockNumbers = [...new Set(logs.map((log) => log.blockNumber).filter(Boolean))];
  const blocks = await Promise.all(
    blockNumbers.map((blockNumber) => client.getBlock({ blockNumber: blockNumber as bigint })),
  );
  const timestamps = new Map(blockNumbers.map((number, index) => [number, Number(blocks[index]?.timestamp ?? 0n)]));

  return logs.map((log) => ({
    vault: log.address as `0x${string}`,
    strategyId: Number(log.args.strategyId ?? 0n),
    tickLower: Number(log.args.tickLower ?? 0),
    tickUpper: Number(log.args.tickUpper ?? 0),
    liquidity: log.args.liquidity ?? 0n,
    txHash: log.transactionHash as `0x${string}`,
    blockNumber: log.blockNumber as bigint,
    timestamp: timestamps.get(log.blockNumber) ?? 0,
  }));
}

async function fetchLive(client: PublicClient): Promise<ChainSnapshot> {
  const count = await client.readContract({
    address: addresses.registry,
    abi: StrategyRegistryAbi,
    functionName: "nextStrategyId",
  });
  const rankedCount = await client.readContract({
    address: addresses.registry,
    abi: StrategyRegistryAbi,
    functionName: "rankedCount",
  });
  const ids = Array.from({ length: Number(count) }, (_, index) => BigInt(index));

  const rows = await Promise.all(
    ids.map(async (id) => {
      const strategy = await client.readContract({
        address: addresses.registry,
        abi: StrategyRegistryAbi,
        functionName: "strategies",
        args: [id],
      });
      const vault = vaultAddress(
        await client.readContract({
          address: addresses.registry,
          abi: StrategyRegistryAbi,
          functionName: "strategyVault",
          args: [id],
        }),
      );
      const [alpha, alphaSamples, shares, tickLower, tickUpper, lastRebalanceTimestamp] =
        await Promise.all([
          client.readContract({ address: addresses.registry, abi: StrategyRegistryAbi, functionName: "getAlpha", args: [id] }),
          client.readContract({ address: addresses.registry, abi: StrategyRegistryAbi, functionName: "alphaSamples", args: [id] }),
          client.readContract({ address: vault, abi: RudderVaultAbi, functionName: "totalSupply" }),
          client.readContract({ address: vault, abi: RudderVaultAbi, functionName: "tickLower" }),
          client.readContract({ address: vault, abi: RudderVaultAbi, functionName: "tickUpper" }),
          client.readContract({ address: vault, abi: RudderVaultAbi, functionName: "lastRebalanceTimestamp" }),
        ]);
      return {
        id: Number(id),
        curator: strategy[0],
        vault,
        alpha,
        alphaSamples,
        shares,
        tickLower: Number(tickLower),
        tickUpper: Number(tickUpper),
        lastRebalanceTimestamp,
        envelope: strategy[1] as unknown as Envelope,
      } satisfies Curator;
    }),
  );

  const [ready, samples, lastObservation, paused] = await Promise.all([
    client.readContract({ address: addresses.hook, abi: RudderHookAbi, functionName: "isOracleReady", args: [poolKey] }),
    client.readContract({ address: addresses.hook, abi: RudderHookAbi, functionName: "observationCount", args: [poolKey] }),
    client.readContract({ address: addresses.hook, abi: RudderHookAbi, functionName: "getLastObservation", args: [poolKey] }),
    client.readContract({ address: addresses.hook, abi: RudderHookAbi, functionName: "paused" }),
  ]);

  let rebalances: RebalanceRecord[] = [];
  try {
    rebalances = await fetchRebalances(client);
  } catch {
    rebalances = snapshot.rebalances;
  }

  let twap = snapshot.twap;
  try {
    twap = await Promise.all(
      [0, 300, 600, 900, 1200, 1500, 1800].map(async (secondsAgo) => ({
        secondsAgo,
        tick: (await readTwapAtOffset(client, secondsAgo)).tick,
      })),
    );
  } catch {
    twap = snapshot.twap;
  }

  return {
    source: "live",
    curators: rows,
    rankedCount,
    rebalances,
    twap,
    oracle: {
      ready,
      samples,
      lastTimestamp: Number(lastObservation[0]),
      lastTickCumulative: lastObservation[1],
      maxAgeSeconds: Number(
        await client.readContract({ address: addresses.hook, abi: RudderHookAbi, functionName: "MAX_OBSERVATION_AGE" }),
      ),
      paused,
    },
  };
}

function vaultAddress(value: `0x${string}`): `0x${string}` {
  return value as `0x${string}`;
}

export function useChainData() {
  const client = usePublicClient({ chainId: CHAIN_ID });
  const query = useQuery<ChainSnapshot>({
    queryKey: ["rudder", "chain", CHAIN_ID],
    enabled: Boolean(client),
    queryFn: async () => {
      if (!client) return snapshot;
      try {
        return await fetchLive(client);
      } catch (error) {
        return {
          ...snapshot,
          source: "snapshot",
          fallbackReason: error instanceof Error ? error.message : "Read failed",
        };
      }
    },
  });

  return {
    data: query.data ?? snapshot,
    isError: query.isError,
    refetch: query.refetch,
  };
}
