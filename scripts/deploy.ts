import { createWalletClient, createPublicClient, http } from "viem";
import { bsc } from "viem/chains";
import { privateKeyToAccount } from "viem/accounts";
import { readFileSync } from "fs";
import hre from "hardhat";

const artifact = JSON.parse(
  readFileSync("./artifacts/contracts/WOLV.sol/WOLV.json", "utf8"),
);

async function main() {
  const networkConfig = hre.config.networks.bsc as {
    accounts: Array<{ get: () => Promise<string> }>;
    url: { getUrl: () => Promise<string> };
  };

  const rawKey = await networkConfig.accounts[0].get();
  const rpcUrl = await networkConfig.url.getUrl();

  const privateKey = (
    rawKey.startsWith("0x") ? rawKey : `0x${rawKey}`
  ) as `0x${string}`;

  const account = privateKeyToAccount(privateKey);

  const walletClient = createWalletClient({
    account,
    chain: bsc,
    transport: http(rpcUrl),
  });

  const publicClient = createPublicClient({
    chain: bsc,
    transport: http(rpcUrl),
  });

  console.log(`🚀 Deploying WOLV from: ${account.address}`);

  const hash = await walletClient.deployContract({
    abi: artifact.abi,
    bytecode: artifact.bytecode as `0x${string}`,
    args: [],
  });

  console.log(`📡 Deploy tx sent! Hash: ${hash}`);
  console.log(`⏳ Waiting for confirmation...`);

  const receipt = await publicClient.waitForTransactionReceipt({
    hash,
    confirmations: 5,
    timeout: 180_000,
  });

  if (receipt.status === "reverted") {
    throw new Error("❌ Deployment transaction reverted!");
  }

  console.log(`✅ WOLV deployed at: ${receipt.contractAddress}`);
  console.log(`   Block: ${receipt.blockNumber}`);
  console.log(`   Gas used: ${receipt.gasUsed}`);
  console.log(`\n👉 Verify with:`);
  console.log(`   npx hardhat verify --network bsc ${receipt.contractAddress}`);
  console.log(`\n🔍 View on BSCScan:`);
  console.log(`   https://bscscan.com/address/${receipt.contractAddress}`);
}

main().catch(console.error);
