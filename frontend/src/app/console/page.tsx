import ConsolePanel from "@/components/ConsolePanel";

export const metadata = {
  title: "Curator console",
  description: "Curator-only range changes with local limit checks and on-chain enforcement.",
};

export default function ConsolePage() {
  return (
    <div className="pt-12 sm:pt-20">
      <h1 className="page-lead mt-5">Every move has a stated limit.</h1>
      <p className="mt-6 max-w-2xl text-slate">
        A curator may rebalance inside the published envelope. The local check explains a rejected
        move in plain language; the vault makes the same check on-chain.
      </p>
      <div className="mt-12">
        <ConsolePanel />
      </div>
    </div>
  );
}
