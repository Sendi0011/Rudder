# ADR-003: Protocol NAV-loss floor
Date: 2026-11-21

## Context
Curators set per-vault envelopes. Before this decision a curator could register a floor such as
`-1000` or `-5000` bps, allowing one accepted rebalance to realize more NAV loss than the protocol's
bound examples assumed. The seeded tiers and local evidence use a `500` bps floor for the balanced
tier, and observed single-rebalance losses sit below that level.

## Decisions
- `EnvelopeLib.PROTOCOL_MAX_NAV_LOSS_BPS` is `500`.
- `EnvelopeLib.validate` rejects any envelope with `maxNavLossBps < -500`.
- Curators may choose any floor from `-500` through `0`; tighter values remain allowed.
- Seeded and test envelopes use `-500` as the deepest floor.

## Consequences
- One accepted rebalance can realize at most 5% NAV loss before the vault reverts. That matches the
  balanced seeded tier and leaves room above the measured local losses.
- Repeated rebalances still compound over a horizon. The 24-hour table in `EVIDENCE.md` reports that
  figure separately.
- Envelopes that previously used `-1000` or `-5000` are tightened to `-500` before registration.

---

Rendered from commit cee9100a4c4fa976728806331a6177b82c568d6d · [View source](https://github.com/Sendi0011/Rudder/blob/cee9100a4c4fa976728806331a6177b82c568d6d/docs/adr/ADR-003-protocol-nav-loss-floor.md)
