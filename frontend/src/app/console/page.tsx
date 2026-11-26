import ConsolePanel from "@/components/ConsolePanel";

export const metadata = {
  title: "For curators",
  description: "Curator-only range changes with local limit checks and on-chain enforcement.",
};

export default function ConsolePage() {
  return (
    <div className="pt-12 sm:pt-20">
      <h1 className="page-title">For curators.</h1>
      <p className="page-intro mt-4">
        A curator may rebalance inside the published limits. The local check explains a rejected
        move in plain language; the vault makes the same check on-chain.
      </p>
      <div className="mt-12">
        <ConsolePanel />
      </div>
    </div>
  );
}
