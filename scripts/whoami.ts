import { privateKeyToAccount } from "viem/accounts";
import hre from "hardhat";

async function main() {
  const networkConfig = hre.config.networks.sepolia as {
    accounts: Array<{ get: () => Promise<string> }>;
  };
  const rawKey = await networkConfig.accounts[0].get();
  const privateKey = (rawKey.startsWith("0x") ? rawKey : `0x${rawKey}`) as `0x${string}`;
  const account = privateKeyToAccount(privateKey);
  console.log(`Deploying from: ${account.address}`);
}

main().catch(console.error);
