import raw from "@/data/snapshot.json";
import type { ChainSnapshot } from "@/lib/types";

export const snapshot: ChainSnapshot = {
  source: "snapshot",
  recordedAt: raw.recordedAt,
  rankedCount: BigInt(raw.curators.length),
  curators: raw.curators.map((entry) => ({
    id: entry.id,
    curator: entry.curator as `0x${string}`,
    vault: entry.vault as `0x${string}`,
    alpha: BigInt(entry.alpha),
    alphaSamples: BigInt(entry.alphaSamples),
    shares: BigInt(entry.shares),
    tickLower: entry.tickLower,
    tickUpper: entry.tickUpper,
    lastRebalanceTimestamp: BigInt(entry.lastRebalanceTimestamp),
    envelope: entry.envelope,
  })),
  rebalances: raw.rebalances.map((entry) => ({
    vault: entry.vault as `0x${string}`,
    strategyId: entry.strategyId,
    tickLower: entry.tickLower,
    tickUpper: entry.tickUpper,
    liquidity: BigInt(entry.liquidity),
    txHash: entry.txHash as `0x${string}`,
    blockNumber: BigInt(entry.blockNumber),
    timestamp: entry.timestamp,
  })),
  oracle: {
    ready: raw.oracle.ready,
    samples: BigInt(raw.oracle.samples),
    lastTimestamp: raw.oracle.lastTimestamp,
    lastTickCumulative: BigInt(raw.oracle.lastTickCumulative),
    maxAgeSeconds: raw.oracle.maxAgeSeconds,
    paused: raw.oracle.paused,
  },
};
