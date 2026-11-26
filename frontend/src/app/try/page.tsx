import JudgePathPanel from "@/components/JudgePathPanel";

export const metadata = {
  title: "Try it in two minutes",
  description: "A short, wallet-only path through mint, deposit, rejected rebalance and withdraw.",
};

export default function TryPage() {
  return (
    <div className="pt-12 sm:pt-20">
      <h1 className="page-title">Try it in two minutes.</h1>
      <p className="page-intro mt-4">
        This path uses test tokens on Unichain Sepolia. Every state-changing step is signed by your
        browser wallet; the app never holds a key or broadcasts for you.
      </p>
      <div className="mt-12">
        <JudgePathPanel />
      </div>
    </div>
  );
}
