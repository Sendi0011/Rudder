# Rudder frontend

Next.js App Router, TypeScript strict, wagmi, viem, TanStack Query, Radix and Tailwind driven by
the tokens in `src/app/globals.css`. The app is a static export: it reads deployed chain state in the
browser and never signs, sends or broadcasts a transaction from a script. Keys are handled only by
the user's browser wallet.

```sh
npm install
npm run dev
npm run typecheck
npm run test:e2e
npm run build
```

Generated inputs are committed under `src/abis`, `src/data` and `content`. Run the sync scripts
before building; `prebuild` and `predev` do this automatically:

```sh
npm run sync:abis
npm run sync:data
npm run sync:docs
```

`src/abis` is generated from `../contracts/out` by `scripts/generate-abis.mjs`.
`src/data` is copied from `../contracts/deployments.json`, `../contracts/seed.json` and
`../evidence/*.json` by `scripts/copy-data.mjs`. `content` is copied from `../README.md`, `../docs/*.md`
and `../docs/adr/*.md` by `scripts/sync-docs.mjs`. Never edit those copies by hand; edit the source
markdown or JSON and rerun the relevant script.

Set `NEXT_PUBLIC_UNICHAIN_SEPOLIA_RPC_URL` to a read-only RPC endpoint for live reads and simulations.
Without it the app uses a public endpoint when available and otherwise shows recorded snapshot data.
Set `NEXT_PUBLIC_MIGRATOR_ADDRESS` only after verifying a deployed `VaultMigrator`; no migrator address
is in the deployment record for chain 1301. Never put a private key in the frontend environment.
