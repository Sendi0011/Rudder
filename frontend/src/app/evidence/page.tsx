import Link from "next/link";
import {
  evidence_churner_alpha,
  evidence_deposit_guard,
  evidence_flow_invariance,
  evidence_invariant_runs,
  evidence_oracle_gas,
  evidence_placebo_curators,
  evidence_prior_art_search,
  evidence_rebalance_alpha_cost,
  evidence_rebalance_bounds,
  evidence_twap_accuracy,
  evidence_worst_case_loss,
} from "@/data";
import { formatCount, formatSigned } from "@/lib/format";

export const metadata = {
  title: "Evidence",
  description: "Measurements, negative results and limits of the Rudder evidence set.",
};

const placebo = evidence_placebo_curators;

const checks = [
  {
    name: "Deposit guard",
    result: `${evidence_deposit_guard.deviationBps} bps deviation reverted against a ${evidence_deposit_guard.capBps} bps cap`,
    detail: `Revert selector ${evidence_deposit_guard.revertSelector}; ${formatCount(evidence_deposit_guard.observations)} observations.`,
  },
  {
    name: "Rebalance bounds",
    result: `Range ${evidence_rebalance_bounds.lower} to ${evidence_rebalance_bounds.upper} (width ${formatCount(evidence_rebalance_bounds.width)}) accepted inside a ${formatCount(evidence_rebalance_bounds.maxRangeWidth)} tick width limit`,
    detail: `Center shift ${formatCount(evidence_rebalance_bounds.centerShift)}, NAV change ${formatSigned(evidence_rebalance_bounds.navChangeBps, "bps")}.`,
  },
  {
    name: "TWAP accuracy",
    result: `${formatCount(evidence_twap_accuracy.observations)} observations, tick error ${formatCount(evidence_twap_accuracy.tickError)}`,
    detail: `Spot ${formatCount(evidence_twap_accuracy.spotTick)}, TWAP ${formatCount(evidence_twap_accuracy.twapTick)}, sqrt deviation ${formatCount(evidence_twap_accuracy.sqrtDeviationBps)} bps.`,
  },
  {
    name: "Flow invariance",
    result: `Alpha delta ${formatCount(evidence_flow_invariance.depositAlphaDelta)} on deposit and ${formatCount(evidence_flow_invariance.withdrawAlphaDelta)} on withdraw`,
    detail: `Relative difference ${formatCount(evidence_flow_invariance.relativeDifferenceBps)} bps.`,
  },
  {
    name: "Handler revert budget",
    result: `${formatCount(evidence_invariant_runs.beforeHandlerReverts)} / ${formatCount(evidence_invariant_runs.beforeHandlerCalls)} reverts, rate ${formatCount(evidence_invariant_runs.beforeRevertRateBps)} bps`,
    detail: `${formatCount(evidence_invariant_runs.runs)} runs at depth ${formatCount(evidence_invariant_runs.depth)}; target ${formatCount(evidence_invariant_runs.targetRevertRateBps)} bps.`,
  },
  {
    name: "Oracle gas",
    result: `${formatCount(evidence_oracle_gas.earlyGas)} gas at ${formatCount(evidence_oracle_gas.earlyObservations)} observations, ${formatCount(evidence_oracle_gas.lateGas)} gas at ${formatCount(evidence_oracle_gas.lateObservations)}`,
    detail: `Capacity ${formatCount(evidence_oracle_gas.capacity)}, max age ${formatCount(evidence_oracle_gas.maxObservationAge)}s.`,
  },
  {
    name: "Rebalance cost",
    result: `${formatSigned(evidence_rebalance_alpha_cost.alphaCostBps, "bps")} alpha cost on rebalance`,
    detail: `NAV loss ${formatSigned(evidence_rebalance_alpha_cost.navLossBps, "bps")}; hold basket unchanged: ${String(evidence_rebalance_alpha_cost.holdBasketUnchanged)}.`,
  },
  {
    name: "Churner resistance",
    result: `${formatCount(evidence_churner_alpha.rankingGapBps)} bps ranking gap after ${formatCount(evidence_churner_alpha.rebalanceCount)} rebalances`,
    detail: `Summed cost ${formatCount(evidence_churner_alpha.summedCostBps)} bps.`,
  },
];

export default function EvidencePage() {
  return (
    <div className="pt-12 sm:pt-20">
      <p className="eyebrow">Evidence · measured, not claimed</p>
      <h1 className="page-lead mt-5">What we measured — and what we did not.</h1>
      <p className="mt-6 max-w-2xl text-slate">
        Rudder is a guardrail for curated liquidity, not a performance claim. The placebo test below
        is a negative result: reactive curators did not beat random curators in this sample.
      </p>

      <section className="mt-12 border-y border-rule py-8" aria-labelledby="placebo-heading">
        <h2 id="placebo-heading" className="text-xl">
          Curator placebo test
        </h2>
        <div className="mt-6 grid gap-8 sm:grid-cols-3">
          <div>
            <p className="eyebrow">Reactive mean</p>
            <p className="figure mt-2">{formatSigned(placebo.reactiveMeanBpsHundredths / 100, "bps", 2)}</p>
          </div>
          <div>
            <p className="eyebrow">Placebo mean</p>
            <p className="figure mt-2">{formatSigned(placebo.placeboMeanBpsHundredths / 100, "bps", 2)}</p>
          </div>
          <div>
            <p className="eyebrow">Static mean</p>
            <p className="figure mt-2">{formatSigned(placebo.staticMeanBpsHundredths / 100, "bps", 2)}</p>
          </div>
        </div>
        <dl className="mt-8 grid gap-3 text-sm sm:grid-cols-2">
          <div>
            <dt className="text-slate">Reactive beats placebo mean</dt>
            <dd>{String(placebo.reactiveBeatsPlaceboMean)}</dd>
          </div>
          <div>
            <dt className="text-slate">z-score</dt>
            <dd>{formatSigned(placebo.reactiveVsPlaceboZScoreTimes100 / placebo.zScoreScale, "", 2)}</dd>
          </div>
          <div>
            <dt className="text-slate">Placebo samples</dt>
            <dd>{formatCount(placebo.placeboSamples)}</dd>
          </div>
          <div>
            <dt className="text-slate">Envelopes / regimes / k</dt>
            <dd>
              {formatCount(placebo.envelopes)} / {formatCount(placebo.regimes)} / {formatCount(placebo.k)}
            </dd>
          </div>
          <div>
            <dt className="text-slate">Worst rebalance loss</dt>
            <dd>{formatSigned(placebo.worstRebalanceLossBpsHundredths / 100, "bps", 2)}</dd>
          </div>
          <div>
            <dt className="text-slate">Max drawdown versus hold</dt>
            <dd>{formatSigned(placebo.maxDrawdownVsHoldBpsHundredths / 100, "bps", 2)}</dd>
          </div>
        </dl>
      </section>

      <section className="mt-12" aria-labelledby="checks-heading">
        <h2 id="checks-heading" className="text-xl">
          Guardrails and invariants
        </h2>
        <div className="table-scroll mt-6">
          <table className="data-table">
            <caption className="sr-only">Evidence checks and observed results</caption>
            <thead>
              <tr>
                <th scope="col">Check</th>
                <th scope="col">Observed result</th>
                <th scope="col">Detail</th>
              </tr>
            </thead>
            <tbody>
              {checks.map((check) => (
                <tr key={check.name}>
                  <th scope="row">{check.name}</th>
                  <td>{check.result}</td>
                  <td className="text-slate">{check.detail}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </section>

      <section className="mt-12 border-y border-rule py-8" aria-labelledby="loss-heading">
        <h2 id="loss-heading" className="text-xl">
          Daily loss budget
        </h2>
        <div className="table-scroll mt-6">
          <table className="data-table">
            <caption className="sr-only">Daily NAV loss budget by configuration</caption>
            <thead>
              <tr>
                <th scope="col">Configuration</th>
                <th scope="col">Bound</th>
                <th scope="col">Observed</th>
                <th scope="col">Rebalances</th>
              </tr>
            </thead>
            <tbody>
              {Object.entries(evidence_worst_case_loss).map(([name, values]) => (
                <tr key={name}>
                  <th scope="row">{name}</th>
                  <td>{formatCount(values.BoundBps)} bps</td>
                  <td>{formatCount(values.ObservedBps)} bps</td>
                  <td>{formatCount(values.Rebalances)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </section>

      <section className="mt-12" aria-labelledby="prior-heading">
        <h2 id="prior-heading" className="text-xl">
          Prior art search
        </h2>
        <p className="mt-3 max-w-2xl text-slate">
          {formatCount(evidence_prior_art_search.total_entries_searched)} hook-directory and hooklist
          entries were searched on {evidence_prior_art_search.run_date}. The curator query returned{" "}
          {formatCount(evidence_prior_art_search.queries[0]?.hit_count)} hits. This is a search record,
          not a uniqueness claim.
        </p>
      </section>

      <p className="mt-12 border-t border-rule pt-5 text-sm text-slate">
        Read the method and raw numbers in{" "}
        <Link className="underline" href="/docs/evidence/">
          the evidence documentation
        </Link>
        .
      </p>
    </div>
  );
}
