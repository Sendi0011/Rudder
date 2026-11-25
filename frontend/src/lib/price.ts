export function sqrtPriceX96ToTick(sqrtPriceX96: bigint): number {
  if (sqrtPriceX96 <= 0n) return 0;
  const ratio = Number(sqrtPriceX96) / 2 ** 96;
  return Math.floor(Math.log(ratio * ratio) / Math.log(1.0001));
}

export function tickToPrice(tick: number): number {
  return 1.0001 ** tick;
}

export function tickToSqrtPriceX96(tick: number): bigint {
  const value = 2 ** 96 * 1.0001 ** (tick / 2);
  if (!Number.isFinite(value) || value <= 0) return 0n;
  return BigInt(Math.floor(value));
}

export function tickToLabel(tick: number): string {
  return tick > 0 ? `+${tick}` : `${tick}`;
}
