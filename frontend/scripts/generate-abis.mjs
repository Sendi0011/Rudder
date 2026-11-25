import { mkdir, readFile, writeFile } from "node:fs/promises";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const frontend = resolve(here, "..");
const repo = resolve(frontend, "..");
const out = join(repo, "contracts", "out");
const destination = join(frontend, "src", "abis");

const targets = [
  ["StrategyRegistry", "StrategyRegistry.sol/StrategyRegistry.json"],
  ["RudderVault", "RudderVault.sol/RudderVault.json"],
  ["RudderHook", "RudderHook.sol/RudderHook.json"],
  ["VaultFactory", "VaultFactory.sol/VaultFactory.json"],
  ["VaultMigrator", "VaultMigrator.sol/VaultMigrator.json"],
  ["TestERC20", "TestERC20.sol/TestERC20.json"],
];

const readJson = async (path) => JSON.parse(await readFile(path, "utf8"));

async function envelopeShape() {
  const wrapper = await readJson(join(out, "EnvelopeLib.t.sol/EnvelopeLibWrapper.json"));
  const validate = wrapper.abi.find(
    (entry) => entry.type === "function" && entry.name === "validate",
  );
  const tuple = validate?.inputs?.[0];
  if (!tuple || tuple.internalType !== "struct Envelope" || !Array.isArray(tuple.components)) {
    throw new Error("No compiled struct Envelope found in EnvelopeLibWrapper artifact");
  }
  return tuple;
}

function patchEnvelope(value, shape) {
  if (!value || typeof value !== "object") return value;
  if (Array.isArray(value)) return value.map((entry) => patchEnvelope(entry, shape));
  const patched = { ...value };
  if (patched.internalType === "struct Envelope" && Array.isArray(patched.components)) {
    patched.components = shape.components.map((component) => ({ ...component }));
  }
  for (const key of ["inputs", "outputs", "components"]) {
    if (patched[key]) patched[key] = patchEnvelope(patched[key], shape);
  }
  return patched;
}

function identifier(name) {
  return name.charAt(0).toLowerCase() + name.slice(1);
}

await mkdir(destination, { recursive: true });
const shape = await envelopeShape();
const patch = await readJson(join(here, "deployed-patch.json"));

for (const [name, artifactPath] of targets) {
  const artifact = await readJson(join(out, artifactPath));
  if (!Array.isArray(artifact.abi)) throw new Error(`Missing ABI in ${artifactPath}`);
  const abi = patchEnvelope(artifact.abi, shape);
  for (const fragment of patch[name]?.abi ?? []) {
    const duplicate = abi.some(
      (entry) =>
        entry.type === fragment.type &&
        entry.name === fragment.name &&
        JSON.stringify(entry.inputs) === JSON.stringify(fragment.inputs),
    );
    if (!duplicate) abi.push(fragment);
  }
  const body =
    `// Generated from ../contracts/out/${artifactPath} by scripts/generate-abis.mjs.\n` +
    `// Deployed-build fragments in scripts/deployed-patch.json are merged for chain 1301.\n` +
    `// Do not edit by hand.\n\n` +
    `export const ${name}Abi = ${JSON.stringify(abi, null, 2)} as const;\n`;
  await writeFile(join(destination, `${name}.ts`), body, "utf8");
  console.log(`wrote src/abis/${name}.ts (${abi.length} ABI entries)`);
}

const index = targets
  .map(([name]) => `export { ${name}Abi } from "./${name}";`)
  .concat(`export const generatedAbiSource = "../contracts/out (Foundry artifacts)";`)
  .join("\n");
await writeFile(join(destination, "index.ts"), `${index}\n`, "utf8");
console.log(`generated ${identifier("index")}.ts`);
