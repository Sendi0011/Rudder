"use client";

import { useEffect, useState } from "react";
import { countdown } from "@/lib/format";

export function ChainStatus({
  source,
  recordedAt,
  fallbackReason,
}: {
  source: "live" | "snapshot";
  recordedAt?: string;
  fallbackReason?: string;
}) {
  return (
    <span className="text-xs text-slate">
      {source === "live" ? "Live reads" : "Recorded snapshot"}
      {recordedAt && source === "snapshot" ? ` · ${recordedAt}` : ""}
      {fallbackReason ? ` · ${fallbackReason}` : ""}
    </span>
  );
}

export function EmptyPanel({ message, action }: { message: string; action?: React.ReactNode }) {
  return (
    <div className="border-y border-rule py-10">
      <p className="max-w-lg text-lg">{message}</p>
      {action ? <div className="mt-4">{action}</div> : null}
    </div>
  );
}

export function ErrorPanel({ message, onRetry }: { message: string; onRetry?: () => void }) {
  return (
    <div className="error" role="alert">
      <p className="font-semibold">Read failed</p>
      <p className="mt-1 text-sm text-slate">{message}</p>
      {onRetry ? (
        <button className="button-secondary mt-4" type="button" onClick={onRetry}>
          Retry read
        </button>
      ) : null}
    </div>
  );
}

export function Countdown({ unlockTime, now }: { unlockTime: number; now: number }) {
  return <span aria-label={`${Math.max(0, unlockTime - now)} seconds remaining`}>{countdown(unlockTime - now)}</span>;
}

export function useClock(intervalMs = 1000) {
  const [now, setNow] = useState(0);
  useEffect(() => {
    const update = () => setNow(Math.floor(Date.now() / 1000));
    update();
    const timer = window.setInterval(update, intervalMs);
    return () => window.clearInterval(timer);
  }, [intervalMs]);
  return now;
}
