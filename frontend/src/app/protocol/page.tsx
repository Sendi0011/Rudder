import { addresses, explorerAddress, migratorAddress, shortAddress } from "@/lib/chain";

export const metadata = {
  title: "Contracts",
  description: "The Rudder call flow, state transitions and deployed addresses.",
};

const flow = [
  { label: "Browser", detail: "wagmi and viem read the deployed contracts" },
  { label: "Wallet", detail: "the user signs; the app never holds a key" },
  { label: "Vault", detail: "custody, shares, range and loss bucket" },
  { label: "Hook", detail: "add check and manipulation-resistant time-weighted price" },
  { label: "PoolManager", detail: "Uniswap v4 liquidity and swaps" },
];

const states = [
  {
    state: "Unseeded",
    entry: "Vault deployed but no position",
    next: "A first deposit and a valid range set the position",
    block: "A range outside the published limits is rejected",
  },
  {
    state: "Range live",
    entry: "One v4 position plus idle balances",
    next: "Swaps accrue fees; the average price and net asset value are read on demand",
    block: "A stale price feed pauses rebalances, not withdrawals",
  },
  {
    state: "Rebalance",
    entry: "Curator submits lower and upper ticks",
    next: "The vault checks the published limits and charges the daily bucket",
    block: "Width, centre shift, price distance, interval, impact or loss can reject",
  },
  {
    state: "Exit or migrate",
    entry: "Liquidity provider holds shares",
    next: "Pro-rata withdrawal; migration moves the whole position",
    block: "A depleted loss bucket never blocks a withdrawal",
  },
];

const deployed = [
  { label: "Pool manager", address: addresses.poolManager },
  { label: "Strategy hook", address: addresses.hook },
  { label: "Strategy registry", address: addresses.registry },
  { label: "Vault factory", address: addresses.factory },
  { label: "Vault implementation", address: addresses.implementation },
  { label: "Vault migrator", address: migratorAddress },
];

export default function ContractsPage() {
  return (
    <div className="pt-12 sm:pt-20">
      <h1 className="page-title">Contracts.</h1>
      <p className="page-intro mt-4">
        A curator proposes a range. The vault checks the published limits, then the hook checks every
        add again. Deposits and withdrawals stay pro-rata and do not depend on the rebalance budget.
      </p>

      <section className="mt-12 border-y border-rule py-8" aria-labelledby="flow-heading">
        <h2 id="flow-heading" className="text-2xl">Call flow</h2>
        <div className="mt-6 overflow-x-auto">
          <svg viewBox="0 0 900 190" className="min-w-[720px]" role="img" aria-label="Flow from browser to wallet to vault to hook to PoolManager">
            {flow.map((step, index) => {
              const x = 10 + index * 180;
              return (
                <g key={step.label}>
                  <rect x={x} y="35" width="150" height="80" fill="var(--color-paper)" stroke="var(--color-ink)" />
                  <text x={x + 12} y="65" fontSize="15" fill="var(--color-ink)" fontWeight="600">
                    {step.label}
                  </text>
                  <text x={x + 12} y="88" fontSize="11" fill="var(--color-slate)">
                    {index === 0 ? "read + connect" : index === 1 ? "sign only" : index === 2 ? "custody" : index === 3 ? "check" : "pool"}
                  </text>
                  {index < flow.length - 1 ? (
                    <path d={`M ${x + 150} 75 L ${x + 178} 75`} stroke="var(--color-accent)" strokeWidth="2" fill="none" />
                  ) : null}
                </g>
              );
            })}
            <path d="M 730 130 L 730 155 L 90 155 L 90 130" stroke="var(--color-slate)" strokeWidth="1.5" fill="none" strokeDasharray="4 5" />
            <text x="410" y="175" textAnchor="middle" fontSize="12" fill="var(--color-slate)">
              state read back through the public RPC — no signature for reads or simulations
            </text>
          </svg>
        </div>
        <div className="mt-6 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          {flow.map((step) => (
            <div key={step.label} className="border-l-2 border-accent pl-3 text-sm">
              <strong>{step.label}</strong>
              <p className="mt-1 text-slate">{step.detail}</p>
            </div>
          ))}
        </div>
      </section>

      <section className="mt-12" aria-labelledby="state-heading">
        <h2 id="state-heading" className="text-2xl">State and failure modes</h2>
        <div className="table-wrap mt-6">
          <table>
            <caption>
              Entry is how a state begins. Next is the allowed transition. What blocks or fails lists the checks that stop it.
            </caption>
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
                  <th scope="row" className="font-normal">{row.state}</th>
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
        <h2 id="addresses-heading" className="text-2xl">Deployed addresses</h2>
        <ul className="mt-4 space-y-2 text-sm">
          {deployed.map((contract) => (
            <li key={contract.label}>
              {contract.label}:{" "}
              <a className="numeric underline" href={explorerAddress(contract.address)}>
                {shortAddress(contract.address)}
              </a>
            </li>
          ))}
        </ul>
      </section>

      <section className="mt-12" aria-labelledby="scope-heading">
        <h2 id="scope-heading" className="text-2xl">Out of scope</h2>
        <ul className="mt-4 list-disc space-y-2 pl-5 text-sm text-slate">
          <li>No audit claim and no guarantee of profit.</li>
          <li>No key custody, no keeper wallet and no transaction broadcast by this app.</li>
          <li>No mainnet deployment and no cross-chain migration in this build.</li>
          <li>No ranking by deposits; the ranking score is the only score and all current scores are zero.</li>
        </ul>
      </section>
    </div>
  );
}
