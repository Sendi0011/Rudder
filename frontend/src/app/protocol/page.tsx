import DocsNote from "@/components/DocsNote";
import { addresses, explorerAddress, shortAddress } from "@/lib/chain";

export const metadata = {
  title: "Protocol",
  description: "The Rudder call flow, state transitions and failure modes.",
};

const flow = [
  { label: "Browser", detail: "wagmi + viem read the deployed contracts" },
  { label: "Wallet", detail: "the user signs; the app never holds a key" },
  { label: "Vault", detail: "custody, shares, range and loss bucket" },
  { label: "Hook", detail: "add gate and manipulation-resistant TWAP" },
  { label: "PoolManager", detail: "Uniswap v4 liquidity and swaps" },
];

const states = [
  {
    state: "Unseeded",
    entry: "Vault deployed but no position",
    next: "A first deposit and a valid range set the position",
    block: "A range outside the envelope is rejected",
  },
  {
    state: "Range live",
    entry: "One v4 position plus idle balances",
    next: "Swaps accrue fees; the TWAP and NAV are read on demand",
    block: "A stale oracle pauses rebalances, not withdrawals",
  },
  {
    state: "Rebalance",
    entry: "Curator submits lower and upper ticks",
    next: "The vault checks the envelope and charges the daily bucket",
    block: "Width, centre shift, TWAP distance, interval, impact or loss can reject",
  },
  {
    state: "Exit or migrate",
    entry: "LP holds shares",
    next: "Pro-rata withdrawal; migration moves the whole position",
    block: "Bad oracle or a depleted bucket never blocks a withdrawal",
  },
];

export default function ProtocolPage() {
  return (
    <div className="pt-12 sm:pt-20">
      <p className="eyebrow">Protocol · chain 1301</p>
      <h1 className="page-lead mt-5">One pool, one range, enforced twice.</h1>
      <p className="mt-6 max-w-2xl text-slate">
        A curator proposes a range. The vault checks the live envelope, then the hook checks every add
        again. Deposits and withdrawals stay pro-rata and do not depend on the rebalance budget.
      </p>

      <section className="mt-12 border-y border-rule py-8" aria-labelledby="flow-heading">
        <h2 id="flow-heading" className="text-xl">
          Call flow
        </h2>
        <div className="mt-6 overflow-x-auto">
          <svg viewBox="0 0 900 190" className="min-w-[720px]" role="img" aria-label="Flow from browser to wallet to vault to hook to PoolManager">
            {flow.map((step, index) => {
              const x = 10 + index * 180;
              return (
                <g key={step.label}>
                  <rect x={x} y="35" width="150" height="80" fill="#EAEFF2" stroke="#14253A" />
                  <text x={x + 12} y="65" fontSize="15" fill="#14253A" fontWeight="600">
                    {step.label}
                  </text>
                  <text x={x + 12} y="88" fontSize="11" fill="#5F7285">
                    {index === 0 ? "read + connect" : index === 1 ? "sign only" : index === 2 ? "custody" : index === 3 ? "gate" : "pool"}
                  </text>
                  {index < flow.length - 1 ? (
                    <path d={`M ${x + 150} 75 L ${x + 178} 75`} stroke="#2C4BD6" strokeWidth="2" fill="none" />
                  ) : null}
                </g>
              );
            })}
            <path d="M 730 130 L 730 155 L 90 155 L 90 130" stroke="#5F7285" strokeWidth="1.5" fill="none" strokeDasharray="4 5" />
            <text x="410" y="175" textAnchor="middle" fontSize="12" fill="#5F7285">
              state read back through the public RPC — no signature for reads or simulations
            </text>
          </svg>
        </div>
        <ol className="mt-6 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          {flow.map((step, index) => (
            <li key={step.label} className="border-l-2 border-cobalt pl-3 text-sm">
              <span className="text-slate">{index + 1}. </span>
              <strong>{step.label}</strong>
              <p className="mt-1 text-slate">{step.detail}</p>
            </li>
          ))}
        </ol>
      </section>

      <section className="mt-12" aria-labelledby="state-heading">
        <h2 id="state-heading" className="text-xl">
          State and failure modes
        </h2>
        <div className="table-scroll mt-6">
          <table className="data-table">
            <caption className="sr-only">Vault states, transitions and rejection reasons</caption>
            <thead>
              <tr>
                <th scope="col">State</th>
                <th scope="col">Entry</th>
                <th scope="col">Next</th>
                <th scope="col">What blocks or fails</th>
              </tr>
            </thead>
            <tbody>
              {states.map((row) => (
                <tr key={row.state}>
                  <th scope="row">{row.state}</th>
                  <td>{row.entry}</td>
                  <td>{row.next}</td>
                  <td className="text-slate">{row.block}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </section>

      <section className="mt-12 border-y border-rule py-8" aria-labelledby="addresses-heading">
        <h2 id="addresses-heading" className="text-xl">
          Deployed surface
        </h2>
        <ul className="mt-4 space-y-2 text-sm">
          <li>
            Strategy registry: <a className="underline" href={explorerAddress(addresses.registry)}>{addresses.registry}</a>
          </li>
          <li>
            Vault factory: <a className="underline" href={explorerAddress(addresses.factory)}>{addresses.factory}</a>
          </li>
          <li>
            Hook: <a className="underline" href={explorerAddress(addresses.hook)}>{shortAddress(addresses.hook)}</a>
          </li>
          <li>
            Pool manager: <a className="underline" href={explorerAddress(addresses.poolManager)}>{shortAddress(addresses.poolManager)}</a>
          </li>
        </ul>
      </section>

      <section className="mt-12" aria-labelledby="scope-heading">
        <h2 id="scope-heading" className="text-xl">
          Out of scope
        </h2>
        <ul className="mt-4 list-disc space-y-2 pl-5 text-sm text-slate">
          <li>No audit claim and no guarantee of profit.</li>
          <li>No key custody, no keeper wallet and no transaction broadcast by this app.</li>
          <li>No mainnet deployment and no cross-chain migration in this build.</li>
          <li>No ranking by deposits; alpha is the only score and all current scores are zero.</li>
        </ul>
      </section>

      <DocsNote href="/docs/architecture/">The contract-level description is in</DocsNote>
    </div>
  );
}
