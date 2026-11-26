import Link from "next/link";
import deployments from "@/data/deployments.json";
import worstCase from "../../../evidence/worst_case_loss.json";

export const metadata = {
  title: "Rudder · Trust the rules, not the manager",
};

const tierLabels: Record<string, string> = {
  conservative: "Conservative",
  balanced: "Balanced",
  aggressive: "Aggressive",
};

const contracts = [
  { label: "Pool manager", address: deployments.poolManager },
  { label: "Strategy hook", address: deployments.rudderHook },
  { label: "Strategy registry", address: deployments.strategyRegistry },
  { label: "Vault factory", address: deployments.vaultFactory },
  { label: "Vault implementation", address: deployments.vaultImplementation },
  { label: "Vault migrator", address: deployments.vaultMigrator },
];

export default function Home() {
  return (
    <>
      <section className="hero">
        <div className="shell">
          <h1>Trust the rules, not the manager.</h1>
          <p>
            Rudder lets a curator manage your Uniswap liquidity, but only
            inside limits published on-chain. Step outside them and the
            transaction fails. You can withdraw whenever you like, even if the
            price feed goes quiet.
          </p>
          <div className="button-row">
            <Link href="/try/" className="button">
              Try it in two minutes
            </Link>
            <Link href="/proof/" className="button-secondary">
              Try to break the rules
            </Link>
          </div>
          <dl className="stat-grid">
            {Object.entries(worstCase).map(([name, values]) => (
              <div className="stat" key={name} data-claim="RUD-029">
                <dt>Worst daily rebalance loss · {tierLabels[name] ?? name}</dt>
                <dd>
                  {values.ObservedBps}
                  <span className="unit">bps</span>
                </dd>
              </div>
            ))}
            <div className="stat" data-claim="RUD-001">
              <dt>Withdrawals that depend on a price feed</dt>
              <dd>0</dd>
            </div>
            <div className="stat" data-claim="RUD-002">
              <dt>Limits a curator cannot exceed</dt>
              <dd>7</dd>
            </div>
          </dl>
        </div>
      </section>

      <section className="section">
        <div className="shell">
          <h2>The problem</h2>
          <ul className="plain-list">
            <li>A passive position leaves the range fixed while the price moves.</li>
            <li>An active manager can move liquidity without a shared limit.</li>
            <li>A withdrawal should not wait on an oracle answer.</li>
          </ul>
        </div>
      </section>

      <section className="section">
        <div className="shell">
          <h2>The solution</h2>
          <ul className="plain-list">
            <li>Published limits travel with the strategy on-chain.</li>
            <li>Every rebalance is checked before it changes liquidity.</li>
            <li>Exits do not call the oracle or ask a curator for permission.</li>
          </ul>
        </div>
      </section>

      <section className="section">
        <div className="shell">
          <h2>How it works</h2>
          <ol className="plain-list">
            <li>Deposit into a curator vault and keep your shares.</li>
            <li data-claim="RUD-002">A curator steers the range inside published limits.</li>
            <li>An outside move is rejected before it reaches the pool.</li>
            <li data-claim="RUD-005">Ranking compares the strategy with simply holding.</li>
            <li data-claim="RUD-001">You can exit at any time, including with a quiet price feed.</li>
          </ol>
          <div className="button-row">
            <Link href="/vaults/" className="button-secondary">
              Pick a curator
            </Link>
          </div>
        </div>
      </section>

      <section className="section">
        <div className="shell">
          <h2>Compare the choices</h2>
          <div className="plain-grid plain-grid--three">
            <article className="panel">
              <h3>Passive LP</h3>
              <p>One range stays in place. The hold basket is the benchmark.</p>
            </article>
            <article className="panel">
              <h3>Trusting a manager</h3>
              <p>A manager can set the range. The searched projects do not share one exit guarantee.</p>
            </article>
            <article className="panel">
              <h3>Rudder</h3>
              <p>
                Limits cover width, centre shift, interval, price impact, NAV
                loss and daily budget. Exits do not consult oracle state.
              </p>
            </article>
          </div>
          <p className="lede">
            Source: <Link href="/docs/prior-art/">prior art</Link> and{" "}
            <Link href="/docs/mandate/">mandate</Link>.
          </p>
        </div>
      </section>

      <section className="section">
        <div className="shell">
          <h2>Contracts</h2>
          <div className="table-wrap">
            <table>
              <caption>Deployed addresses from contracts/deployments.json.</caption>
              <thead>
                <tr>
                  <th scope="col">Contract</th>
                  <th scope="col">Address</th>
                </tr>
              </thead>
              <tbody>
                {contracts.map((contract) => (
                  <tr key={contract.label}>
                    <td>{contract.label}</td>
                    <td className="mono">{contract.address}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      </section>
    </>
  );
}
