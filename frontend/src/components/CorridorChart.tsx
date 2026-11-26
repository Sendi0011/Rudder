"use client";

import { useMemo } from "react";
import { formatCount, formatSigned } from "@/lib/format";
import type { ChainSnapshot, Curator } from "@/lib/types";

const W = 900;
const H = 420;
const LEFT = 58;
const RIGHT = 24;
const TOP = 28;
const BOTTOM = 46;

interface Props {
  data: ChainSnapshot;
  curator: Curator;
  compact?: boolean;
}

export default function CorridorChart({ data, curator, compact = false }: Props) {
  const chart = useMemo(() => {
    const history = data.rebalances
      .filter((entry) => entry.vault.toLowerCase() === curator.vault.toLowerCase())
      .sort((a, b) => (a.blockNumber < b.blockNumber ? -1 : 1));
    const twapTick = data.twap[0]?.tick ?? 0;
    const bandHalf = Math.abs(curator.envelope.maxTwapDistanceTicks);
    const segments = [
      ...history.map((entry) => ({
        lower: entry.tickLower,
        upper: entry.tickUpper,
        label: new Date(entry.timestamp * 1000).toISOString().slice(11, 16),
        rebalance: true,
      })),
      { lower: curator.tickLower, upper: curator.tickUpper, label: "now", rebalance: false },
    ];
    const firstTs = history[0]?.timestamp;
    const xs = segments.map((_, index) => {
      if (segments.length === 1) return 1;
      return index / (segments.length - 1);
    });
    const allTicks = segments.flatMap((segment) => [segment.lower, segment.upper]);
    allTicks.push(twapTick - bandHalf, twapTick + bandHalf);
    data.twap.forEach((point) => allTicks.push(point.tick));
    const minTick = Math.min(...allTicks) - 40;
    const maxTick = Math.max(...allTicks) + 40;
    const plotW = W - LEFT - RIGHT;
    const plotH = H - TOP - BOTTOM;
    const x = (fraction: number) => LEFT + fraction * plotW;
    const y = (tick: number) => TOP + ((maxTick - tick) / (maxTick - minTick)) * plotH;

    const rangePath = (key: "lower" | "upper") =>
      segments
        .map((segment, index) => {
          const px = x(xs[index] ?? 0);
          const py = y(segment[key]);
          if (index === 0) return `M ${px} ${py}`;
          const prevX = x(xs[index - 1] ?? 0);
          return `L ${prevX} ${py} L ${px} ${py}`;
        })
        .join(" ");

    const upperPath = rangePath("upper");
    const lowerPath = rangePath("lower");
    const area = `${upperPath} ${[...segments].reverse().map((segment, index) => {
      const reversedIndex = segments.length - 1 - index;
      return `L ${x(xs[reversedIndex] ?? 0)} ${y(segment.lower)}`;
    }).join(" ")} Z`;

    const orderedTwap = [...data.twap].reverse();
    const twapPath = orderedTwap
      .map((point, index) => {
        const px = LEFT + (index / Math.max(1, orderedTwap.length - 1)) * plotW;
        const py = y(point.tick);
        return `${index === 0 ? "M" : "L"} ${px} ${py}`;
      })
      .join(" ");

    const gridTicks = Array.from({ length: 5 }, (_, index) =>
      Math.round(minTick + ((maxTick - minTick) * index) / 4),
    );

    return {
      xs,
      segments,
      x,
      y,
      area,
      upperPath,
      lowerPath,
      twapPath,
      bandTop: y(twapTick + bandHalf),
      bandBottom: y(twapTick - bandHalf),
      twapY: y(twapTick),
      gridTicks,
      firstLabel: firstTs ? new Date(firstTs * 1000).toISOString().slice(11, 16) : "start",
      lastLabel: segments.at(-1)?.label ?? "now",
      twapTick,
      bandHalf,
    };
  }, [data.rebalances, data.twap, curator]);

  return (
    <figure className="m-0">
      <svg
        viewBox={`0 0 ${W} ${H}`}
        className="block w-full"
        role="img"
        aria-labelledby={`corridor-title-${curator.id}`}
        preserveAspectRatio="xMidYMid meet"
      >
        <title id={`corridor-title-${curator.id}`}>
          Range history for strategy {curator.id}: time-weighted average price, allowed band and actual range
        </title>
        <desc>
          The shaded band shows the published distance limit. Accent lines show the vault range. The
          dark line shows the time-weighted average price. Vertical marks are rebalances.
        </desc>
        <rect x={LEFT} y={TOP} width={W - LEFT - RIGHT} height={H - TOP - BOTTOM} fill="var(--color-paper)" />
        <rect
          x={LEFT}
          y={chart.bandTop}
          width={W - LEFT - RIGHT}
          height={chart.bandBottom - chart.bandTop}
          fill="var(--color-accent-wash)"
        />
        {chart.gridTicks.map((tick) => (
          <g key={tick}>
            <line x1={LEFT} x2={W - RIGHT} y1={chart.y(tick)} y2={chart.y(tick)} stroke="var(--color-slate)" strokeOpacity="0.28" />
            <text className="numeric" x={LEFT - 10} y={chart.y(tick) + 4} textAnchor="end" fontSize="11" fill="var(--color-slate)">
              {formatSigned(tick, "ticks")}
            </text>
          </g>
        ))}
        <path d={chart.area} fill="var(--color-accent)" fillOpacity="0.1" />
        <path d={chart.upperPath} fill="none" stroke="var(--color-accent)" strokeWidth="2.5" />
        <path d={chart.lowerPath} fill="none" stroke="var(--color-accent)" strokeWidth="2.5" />
        {chart.segments.map((segment, index) =>
          segment.rebalance ? (
            <g key={`${segment.label}-${index}`}>
              <line
                x1={chart.x(chart.xs[index] ?? 0)}
                x2={chart.x(chart.xs[index] ?? 0)}
                y1={TOP}
                y2={H - BOTTOM}
                stroke="var(--color-ink)"
                strokeOpacity="0.45"
                strokeDasharray="3 5"
              />
              <circle cx={chart.x(chart.xs[index] ?? 0)} cy={chart.y(segment.upper)} r="4" fill="var(--color-ink)" />
              <circle cx={chart.x(chart.xs[index] ?? 0)} cy={chart.y(segment.lower)} r="4" fill="var(--color-ink)" />
            </g>
          ) : null,
        )}
        <path d={chart.twapPath} fill="none" stroke="var(--color-ink)" strokeWidth="2" />
        <line x1={LEFT} x2={W - RIGHT} y1={chart.twapY} y2={chart.twapY} stroke="var(--color-ink)" strokeOpacity="0.25" strokeDasharray="2 6" />
        <text className="numeric" x={W - RIGHT} y={chart.twapY - 8} textAnchor="end" fontSize="11" fill="var(--color-ink)">
          TWAP {formatSigned(chart.twapTick, "ticks")}
        </text>
        <text className="numeric" x={LEFT} y={H - 14} fontSize="11" fill="var(--color-slate)">{chart.firstLabel} UTC</text>
        <text className="numeric" x={W - RIGHT} y={H - 14} textAnchor="end" fontSize="11" fill="var(--color-slate)">{chart.lastLabel} UTC</text>
      </svg>
      <figcaption className="mt-3 flex flex-wrap gap-x-6 gap-y-1 text-xs text-slate">
        <span>Shaded band: allowed distance ±{formatCount(chart.bandHalf)} ticks</span>
        <span>Accent: vault range {curator.tickLower} to {curator.tickUpper}</span>
        <span>Dark line: time-weighted average price</span>
        <span>Vertical marks: {formatCount(chart.segments.filter((segment) => segment.rebalance).length)} rebalances</span>
        {compact ? null : <span>Source: registry limits, vault range and rebalance logs</span>}
      </figcaption>
    </figure>
  );
}
