import { createPublicClient, http } from "viem";
import { sepolia } from "viem/chains";

const client = createPublicClient({ chain: sepolia, transport: http() });

const addresses = {
  "WOLV (old)":    "0xb99a933b3039322cb6fe32c6cdb967704b166fcd",
  "Staking":       "0x4b62efee5695ed55cd362a0b818f4c5f9694322b",
  "Pool":          "0xb233cf74b14abf9d9702d585c540030125599579",
};

async function main() {
  console.log("Checking Sepolia contracts...\n");
  for (const [name, addr] of Object.entries(addresses)) {
    const code = await client.getBytecode({ address: addr as `0x${string}` });
    console.log(`${name}: ${code ? "✅ Deployed" : "❌ Not found"} — ${addr}`);
  }
}

main().catch(console.error);
