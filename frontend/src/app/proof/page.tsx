import ProofPanel from "@/components/ProofPanel";

export const metadata = {
  title: "Live proof",
  description: "Simulate a curator rebalance against the deployed vault without signing a transaction.",
};

export default function ProofPage() {
  return (
    <div className="pt-12 sm:pt-20">
      <h1 className="page-lead mt-5">A rejected move, proved live.</h1>
      <p className="mt-6 max-w-2xl text-slate">
        The call runs against the deployed contract on Unichain Sepolia. The page shows the exact
        revert reason and never asks for a signature.
      </p>
      <div className="mt-12">
        <ProofPanel />
      </div>
    </div>
  );
}
