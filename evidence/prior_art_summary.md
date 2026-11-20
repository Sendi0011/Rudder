# Prior-art search

Run date: 2026-11-20

## Datasets

| Dataset | Commit | Entries |
| --- | --- | ---: |
| uhi-hook-directory | `9c2faeb267778f07de8430ea0ca98b29134df630` | 759 |
| uniswap-hooklist | `3017a8368cb2d610d63dacff7feba8a850e9186d` | 5271 |

Total entries searched: 6030

## Queries

| Query | Regex | Hits | Directory | Hooklist |
| --- | --- | ---: | ---: | ---: |
| curator | `\bcurator(?:s|ial)?\b` | 7 | 2 | 5 |
| delegation_management | `\b(delegat(?:e|ed|es|ion|ing)|manager|vault|strategist)\b` | 1221 | 145 | 1076 |
| range_rebalance | `\b(range|rebalanc(?:e|es|ed|ing))\b` | 511 | 205 | 306 |
| mandate_bounds | `\b(mandate|envelope|guardrail|bounded|limits?)\b` | 284 | 125 | 159 |
| performance_fee_hwm | `performance\s+fee|high[- ]?water[- ]?mark` | 0 | 0 | 0 |
| timelock | `\btimelock(?:s|ed)?\b|\btime[- ]lock(?:s|ed)?\b` | 27 | 8 | 19 |
| gated_liquidity_adds | `\b(?:gated|whitelist(?:ed)?)\b[\s\S]{0,200}\b(?:liquidity|addLiquidity|beforeAddLiquidity)\b|\bbeforeAddLiquidity\b[\s\S]{0,200}\b(?:revert|only)\b` | 102 | 9 | 93 |
| twap_tick_oracle | `\bTWAP\b|tick[- ]cumulative|tickCumulative` | 167 | 35 | 132 |
| hold_benchmark | `\bhold\b[\s\S]{0,80}\bbenchmark\b|\bbenchmark\b[\s\S]{0,80}\bhold\b` | 0 | 0 | 0 |

## Manual findings

- performance_fee_hwm: reproduced=true; none of the directory entries searched mention a performance fee or high-water mark.
- curator_entry_count: reproduced=true; curator appears in two directory entries, Gainswap and PumpUp.
