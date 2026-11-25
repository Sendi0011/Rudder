import DocsNote from "@/components/DocsNote";
import PositionsPanel from "@/components/PositionsPanel";

export const metadata = {
  title: "My positions",
  description: "Shares, unclaimed fees, permissions and migration for the connected wallet.",
};

export default function PositionsPage() {
  return (
    <div className="pt-12 sm:pt-20">
      <h1 className="page-lead mt-5">Your position, your exit.</h1>
      <p className="mt-6 max-w-2xl text-slate">
        Shares stay in the vault you chose. Fees are claimable, and migration moves the whole position
        only after your wallet approves it.
      </p>
      <div className="mt-12 border-t border-rule pt-8">
        <PositionsPanel />
      </div>
      <DocsNote href="/docs/architecture/">Vault shares, fees, permissions and migration are described in</DocsNote>
    </div>
  );
}
