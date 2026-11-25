"use client";

import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { useState } from "react";
import { WagmiProvider, createConfig, http } from "wagmi";
import { injected } from "wagmi/connectors/injected";
import { rpcUrl, unichainSepolia } from "@/lib/chain";

const config = createConfig({
  chains: [unichainSepolia],
  connectors: [injected({ shimDisconnect: true })],
  transports: { [unichainSepolia.id]: http(rpcUrl) },
  ssr: false,
});

export default function Providers({ children }: { children: React.ReactNode }) {
  const [queryClient] = useState(
    () => new QueryClient({ defaultOptions: { queries: { retry: 1, staleTime: 15_000 } } }),
  );

  return (
    <WagmiProvider config={config}>
      <QueryClientProvider client={queryClient}>{children}</QueryClientProvider>
    </WagmiProvider>
  );
}
