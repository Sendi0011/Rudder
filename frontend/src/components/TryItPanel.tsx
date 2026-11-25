"use client";

import Link from "next/link";
import { useState } from "react";
import ActionDrawer from "@/components/ActionDrawer";

export default function TryItPanel() {
  const [open, setOpen] = useState(false);

  return (
    <aside aria-labelledby="try-heading" className="border-l-0 lg:border-l lg:border-rule lg:pl-8">
      <h2 id="try-heading" className="text-xl">
        Try it
      </h2>
      <p className="mt-2 text-slate">
        Connect a browser wallet, deposit test tokens into a vault and withdraw your shares.
      </p>
      <button type="button" className="action mt-5 w-full" onClick={() => setOpen(true)}>
        Deposit
      </button>
      <button type="button" className="action action-quiet mt-3 w-full" onClick={() => setOpen(true)}>
        Withdraw
      </button>
      <p className="mt-4 text-xs text-slate">
        The app signs nothing on its own. Your wallet approves each step.
      </p>
      <Link className="mt-3 block text-sm text-slate underline" href="/docs/how-it-works/">
        Read how it works first
      </Link>
      <Link className="mt-2 block text-sm text-ink underline" href="/try/">
        Open the full judge path
      </Link>
      <ActionDrawer open={open} onOpenChange={setOpen} />
    </aside>
  );
}
