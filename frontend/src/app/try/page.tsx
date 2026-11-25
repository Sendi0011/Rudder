import DocsNote from "@/components/DocsNote";
import JudgePathPanel from "@/components/JudgePathPanel";

export const metadata = {
  title: "Judge path",
  description: "A short, wallet-only path through mint, deposit, rejected rebalance and withdraw.",
};

export default function TryPage() {
  return (
    <div className="pt-12 sm:pt-20">
      <p className="eyebrow">Judge path · about two minutes</p>
      <h1 className="page-lead mt-5">Fund, deposit, prove the guard, exit.</h1>
      <p className="mt-6 max-w-2xl text-slate">
        This path uses test tokens on Unichain Sepolia. Every state-changing step is signed by your
        browser wallet; the app never holds a key or broadcasts for you.
      </p>
      <div className="mt-12">
        <JudgePathPanel />
      </div>
      <DocsNote href="/docs/demo/">The same path is described in</DocsNote>
    </div>
  );
}
