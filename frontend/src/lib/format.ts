export const PLACEHOLDER = "--";

type Numeric = number | bigint | null | undefined;

function present(value: Numeric): value is number | bigint {
  if (value === null || value === undefined) return false;
  return typeof value === "bigint" || Number.isFinite(value);
}

function asNumber(value: number | bigint): number {
  return typeof value === "bigint" ? Number(value) : value;
}

function safeNumber(value: number | bigint): number {
  const number = asNumber(value);
  return Object.is(number, -0) ? 0 : number;
}

function round(value: number, digits: number): number {
  const factor = 10 ** digits;
  return Math.sign(value) * Math.round(Math.abs(value) * factor) / factor;
}

export function formatCount(value: Numeric): string {
  if (!present(value)) return PLACEHOLDER;
  return new Intl.NumberFormat("en-US", { maximumFractionDigits: 0 }).format(value);
}

export function formatBps(value: Numeric, digits = 2): string {
  if (!present(value)) return PLACEHOLDER;
  const safe = safeNumber(value);
  const rounded = round(safe, digits);
  if (rounded === 0 && safe !== 0) return `${safe < 0 ? "-" : ""}<${10 ** -digits} bps`;
  return `${new Intl.NumberFormat("en-US", { maximumFractionDigits: digits }).format(rounded)} bps`;
}

export function formatSigned(
  value: Numeric,
  unit: "bps" | "ticks" | "" = "",
  digits = 0,
): string {
  if (!present(value)) return PLACEHOLDER;
  const safe = safeNumber(value);
  const rounded = round(safe, digits);
  const suffix = unit ? ` ${unit}` : "";
  if (rounded === 0 && safe !== 0) return `${safe < 0 ? "-" : ""}<${10 ** -digits}${suffix}`;
  const prefix = rounded > 0 ? "+" : "";
  return `${prefix}${new Intl.NumberFormat("en-US", { maximumFractionDigits: digits }).format(rounded)}${suffix}`;
}

export function formatToken(value: bigint | null | undefined, decimals = 18, maxFractionDigits = 4): string {
  if (!present(value)) return PLACEHOLDER;
  const raw = asNumber(value) / 10 ** decimals;
  if (!Number.isFinite(raw)) return PLACEHOLDER;
  if (raw === 0) return "0";
  if (Math.abs(raw) < 10 ** -maxFractionDigits) return `<${10 ** -maxFractionDigits}`;
  const digits = Math.abs(raw) >= 1000 ? 2 : maxFractionDigits;
  const formatted = new Intl.NumberFormat("en-US", { maximumFractionDigits: digits }).format(raw);
  if (formatted.length > 18) {
    return new Intl.NumberFormat("en-US", { notation: "compact", maximumFractionDigits: 2 }).format(raw);
  }
  return formatted;
}

export function formatPercent(value: number | null | undefined, digits = 2): string {
  if (!present(value)) return PLACEHOLDER;
  const safe = safeNumber(value);
  return `${new Intl.NumberFormat("en-US", { maximumFractionDigits: digits }).format(round(safe * 100, digits))}%`;
}

export function relativeAge(timestampSeconds: number | null | undefined, nowSeconds: number): string {
  if (!present(timestampSeconds)) return PLACEHOLDER;
  const delta = Math.max(0, Math.floor(nowSeconds - asNumber(timestampSeconds)));
  if (delta < 60) return `${delta}s ago`;
  if (delta < 3600) return `${Math.floor(delta / 60)}m ago`;
  if (delta < 86400) return `${Math.floor(delta / 3600)}h ago`;
  return `${Math.floor(delta / 86400)}d ago`;
}

export function countdown(secondsRemaining: number | null | undefined): string {
  if (!present(secondsRemaining)) return PLACEHOLDER;
  const seconds = Math.max(0, Math.floor(asNumber(secondsRemaining)));
  const hours = Math.floor(seconds / 3600);
  const minutes = Math.floor((seconds % 3600) / 60);
  const rest = seconds % 60;
  return `${hours.toString().padStart(2, "0")}:${minutes.toString().padStart(2, "0")}:${rest.toString().padStart(2, "0")}`;
}
