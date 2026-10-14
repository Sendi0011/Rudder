# Feedback: Uniswap v4 Developer Friction (Rudder, UHI11)

Real friction encountered while building Rudder. Every item is something we hit directly
in this repository; file references point at the code where it surfaced.

## 1. `BaseHook` is not in `v4-core` or `v4-periphery`
The canonical `BaseHook` used by almost every tutorial lives in a separate repo
(`Uniswap/v4-hooks-public`), not in `v4-core` or `v4-periphery`. Our initial import
`import {BaseHook} from "v4-periphery/utils/BaseHook.sol"` failed to resolve.
We ended up implementing `IHooks` directly. This is a real onboarding trap: the most
commonly referenced base contract is not where a new v4 developer expects it.

## 2. `IHooks` signature drift between revisions
`afterAddLiquidity` / `afterRemoveLiquidity` in the checked-out `v4-core` take a 6th
argument `feesAccrued` (`BalanceDelta`) that older examples omit; `afterSwap` returns
`(bytes4, int128)`, not `(bytes4)`. Getting these wrong produces "contract should be
marked abstract" / "missing implementation" errors that are not obvious to diagnose.
A versioned interface reference (or an interface changelog) would save hours.

## 3. Two different `getSlot0` entry points
There is no `getSlot0` on the `IPoolManager` interface. Reading pool price requires the
`StateLibrary` extension (`StateLibrary.getSlot0(manager, poolId)`) or the `Extsload`
pattern. Coming from v3, `pool.slot0()` is the muscle-memory call, and its absence is
surprising.

## 4. Remappings when vendoring `v4-core` and `v4-periphery` together
`v4-periphery` vendors its own copy of `v4-core` under `lib/v4-core`, so `openzeppelin-contracts`
and `forge-std` resolve through `lib/v4-core/lib/...`. We had to run
`git submodule update --init --recursive` inside each dependency before `forge-std/Test.sol`
would resolve. Submodule recursion depth (v4-core → openzeppelin → forge-std → ds-test) is
three levels deep, and a shallow clone leaves the test framework missing.

## 5. `via-ir` is effectively required for non-trivial vault logic
Our `withdraw` (fee crystallization, proportional basket math, oracle branch) tripped
"Stack too deep" under the default pipeline. Enabling `--via-ir` resolved it. For a hook
plus vault project this is not optional; the default dev experience should surface it earlier.

## 6. Oracle staleness/threshold design has no blessed default in v4
There is no built-in TWAP observation helper on v4 pools analogous to v3's
`observe()`; hook authors must build and index their own observation storage. For
curated-liquidity hooks that depend on TWAP for NAV and envelope checks, this is
non-trivial to get right (ring-buffer growth, staleness, sparse-swap pools) and
deserves a documented reference implementation.

## 7. Minor: Foundry lint noise
`forge build` emits many lint advisories (`unaliased-plain-import`, `unused-import`,
`screaming-snake-case-immutable`, `unwrapped-modifier-logic`) mixed into compiler output.
These are fine to have, but they obscure real compiler errors in logs; a separate
`forge lint` stream would be cleaner.
