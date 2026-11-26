import PositionsPanel from "@/components/PositionsPanel";

export const metadata = {
  title: "Your deposits",
  description: "Shares, unclaimed fees, permissions and migration for the connected wallet.",
};

export default function PositionsPage() {
  return (
    <div className="pt-12 sm:pt-20">
      <h1 className="page-title">Your deposits.</h1>
      <p className="page-intro mt-4">
        Shares stay in the vault you chose. Fees are claimable, and migration moves the whole position
        only after your wallet approves it.
      </p>
      <div className="mt-12 border-t border-rule pt-8">
        <PositionsPanel />
      </div>
    </div>
  );
}
