export interface Envelope {
  maxRangeWidth: number;
  maxCenterShift: number;
  maxTwapDistanceTicks: number;
  minRebalanceInterval: number;
  maxPriceImpactBps: number;
  maxNavLossBps: number;
  maxDailyNavLossBps: number;
}

export interface Curator {
  id: number;
  curator: `0x${string}`;
  vault: `0x${string}`;
  alpha: bigint;
  alphaSamples: bigint;
  shares: bigint;
  tickLower: number;
  tickUpper: number;
  lastRebalanceTimestamp: bigint;
  envelope: Envelope;
}

export interface RebalanceRecord {
  vault: `0x${string}`;
  strategyId: number;
  tickLower: number;
  tickUpper: number;
  liquidity: bigint;
  txHash: `0x${string}`;
  blockNumber: bigint;
  timestamp: number;
}

export interface OracleState {
  ready: boolean;
  samples: bigint;
  lastTimestamp: number;
  lastTickCumulative: bigint;
  maxAgeSeconds: number;
  paused: boolean;
}

export interface ChainSnapshot {
  source: "live" | "snapshot";
  recordedAt?: string;
  fallbackReason?: string;
  curators: Curator[];
  rebalances: RebalanceRecord[];
  oracle: OracleState;
  rankedCount: bigint;
  twap: { secondsAgo: number; tick: number }[];
}

export interface ChartPoint {
  label: string;
  timestamp: number;
  twapTick: number;
  lower: number;
  upper: number;
  rebalance?: boolean;
}
